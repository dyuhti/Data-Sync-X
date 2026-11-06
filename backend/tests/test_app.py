import copy
import sys
import unittest
from pathlib import Path
from uuid import uuid4
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import app as app_module


class InMemoryCollection:
    def __init__(self):
        self.documents = {}

    def find_one(self, query):
        document = self.documents.get(query["id"])
        return copy.deepcopy(document) if document is not None else None

    def insert_one(self, document):
        if document["id"] in self.documents:
            raise RuntimeError("duplicate key")
        self.documents[document["id"]] = copy.deepcopy(document)

    def replace_one(self, query, document):
        self.documents[query["id"]] = copy.deepcopy(document)


class BackendConflictTests(unittest.TestCase):
    def setUp(self):
        self.collection = InMemoryCollection()
        app_module.app.config["TESTING"] = True
        self.client = app_module.app.test_client()
        self.collection_patcher = patch(
            "app._get_note_collection",
            return_value=(None, self.collection),
        )
        self.collection_patcher.start()

    def tearDown(self):
        self.collection_patcher.stop()

    def note_payload(self, note_id=None, title="Title", content="Content"):
        return {
            "id": note_id or str(uuid4()),
            "title": title,
            "content": content,
            "version": 1,
            "updated_at": "2026-01-01T00:00:00+00:00",
            "is_deleted": False,
        }

    def create(self, payload):
        return self.client.post("/api/notes", json=payload)

    def test_normal_update_succeeds(self):
        payload = self.note_payload()
        self.assertEqual(self.create(payload).status_code, 201)

        response = self.client.put(
            f"/api/notes/{payload['id']}",
            json={
                "title": "Changed",
                "content": "Updated",
                "base_version": 1,
            },
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["note"]["version"], 2)

    def test_second_update_from_version_one_conflicts(self):
        payload = self.note_payload()
        self.create(payload)
        first = self.client.put(
            f"/api/notes/{payload['id']}",
            json={"title": "First", "content": "One", "base_version": 1},
        )
        second = self.client.put(
            f"/api/notes/{payload['id']}",
            json={"title": "Second", "content": "Two", "base_version": 1},
        )

        self.assertEqual(first.status_code, 200)
        self.assertEqual(second.status_code, 409)
        conflict = second.get_json()
        self.assertEqual(conflict["conflict_type"], "UPDATE_UPDATE")
        self.assertEqual(conflict["remote_payload"]["content"], "One")
        self.assertEqual(self.collection.documents[payload["id"]]["content"], "One")

    def test_normal_delete_succeeds(self):
        payload = self.note_payload()
        self.create(payload)

        response = self.client.delete(
            f"/api/notes/{payload['id']}", json={"base_version": 1}
        )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.get_json()["note"]["is_deleted"])

    def test_stale_delete_conflicts(self):
        payload = self.note_payload()
        self.create(payload)
        self.client.put(
            f"/api/notes/{payload['id']}",
            json={"title": "Changed", "content": "New", "base_version": 1},
        )

        response = self.client.delete(
            f"/api/notes/{payload['id']}", json={"base_version": 1}
        )

        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.get_json()["conflict_type"], "UPDATE_DELETE")
        self.assertFalse(self.collection.documents[payload["id"]]["is_deleted"])

    def test_update_against_deleted_note_conflicts(self):
        payload = self.note_payload()
        self.create(payload)
        self.client.delete(
            f"/api/notes/{payload['id']}", json={"base_version": 1}
        )

        response = self.client.put(
            f"/api/notes/{payload['id']}",
            json={"title": "Changed", "content": "New", "base_version": 1},
        )

        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.get_json()["conflict_type"], "UPDATE_DELETE")

    def test_create_new_id_succeeds(self):
        response = self.create(self.note_payload())
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.get_json()["status"], "ok")

    def test_identical_create_retry_is_idempotent(self):
        payload = self.note_payload()
        first = self.create(payload)
        second = self.create(payload)

        self.assertEqual(first.status_code, 201)
        self.assertEqual(second.status_code, 200)
        self.assertEqual(second.get_json()["note"]["id"], payload["id"])

    def test_different_duplicate_create_conflicts(self):
        payload = self.note_payload()
        self.create(payload)
        duplicate = dict(payload, content="Different")

        response = self.create(duplicate)

        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.get_json()["conflict_type"], "DUPLICATE_INSERT")
        self.assertEqual(
            self.collection.documents[payload["id"]]["content"], "Content"
        )

    def test_update_requires_base_version(self):
        payload = self.note_payload()
        self.create(payload)

        response = self.client.put(
            f"/api/notes/{payload['id']}",
            json={"title": "Changed", "content": "New"},
        )

        self.assertEqual(response.status_code, 400)

    def test_deleted_delete_is_idempotent(self):
        payload = self.note_payload()
        self.create(payload)
        first = self.client.delete(
            f"/api/notes/{payload['id']}", json={"base_version": 1}
        )
        second = self.client.delete(
            f"/api/notes/{payload['id']}", json={"base_version": 1}
        )

        self.assertEqual(first.status_code, 200)
        self.assertEqual(second.status_code, 200)
        self.assertEqual(second.get_json()["note"]["version"], 2)


if __name__ == "__main__":
    unittest.main()
