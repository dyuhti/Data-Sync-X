import os
from datetime import datetime, timezone
from uuid import UUID

from flask import Flask, jsonify, request
from flask_cors import CORS
from pymongo.errors import DuplicateKeyError, PyMongoError

from database import check_mongodb_connection, get_notes_collection

app = Flask(__name__)
CORS(app)

NOTE_FIELDS = ("id", "title", "content", "version", "updated_at", "is_deleted")


def _utc_timestamp() -> str:
    return datetime.now(timezone.utc).isoformat()


def _serialize_note(note):
    serialized_note = dict(note)
    serialized_note.pop("_id", None)
    return {field: serialized_note[field] for field in NOTE_FIELDS}


def _json_error(message, status):
    return jsonify({"status": "error", "message": message}), status


def _parse_note_payload(payload, *, require_id):
    if not isinstance(payload, dict):
        raise ValueError("Request body must be a JSON object.")

    required_fields = ("id", "title", "content") if require_id else ("title", "content")
    missing_fields = [
        field for field in required_fields
        if field not in payload
    ]
    if missing_fields:
        raise ValueError("Missing required fields: " + ", ".join(missing_fields))

    if require_id:
        try:
            UUID(payload["id"])
        except (AttributeError, TypeError, ValueError):
            raise ValueError("id must be a valid UUID string.")

    for field in ("title", "content"):
        if not isinstance(payload[field], str):
            raise ValueError(f"{field} must be a string.")

    if "version" in payload and (
        not isinstance(payload["version"], int) or isinstance(payload["version"], bool)
        or payload["version"] < 1
    ):
        raise ValueError("version must be a positive integer.")

    if "is_deleted" in payload and not isinstance(payload["is_deleted"], bool):
        raise ValueError("is_deleted must be a boolean.")

    if "updated_at" in payload and not isinstance(payload["updated_at"], str):
        raise ValueError("updated_at must be an ISO timestamp string.")

def _get_note_collection():
    return get_notes_collection()


@app.get("/health")
def health_check():
    return jsonify({"status": "ok"})


@app.get("/health/database")
def database_health_check():
    try:
        check_mongodb_connection()
    except (PyMongoError, RuntimeError) as error:
        return jsonify({"status": "error", "message": str(error)}), 503

    return jsonify({"status": "ok", "database": "mongodb"})


@app.get("/api/notes")
def get_notes():
    client = None
    try:
        client, collection = _get_note_collection()
        notes = [
            _serialize_note(note)
            for note in collection.find({}).sort("updated_at", -1)
        ]
        return jsonify({"status": "ok", "notes": notes})
    except (PyMongoError, RuntimeError) as error:
        return _json_error(f"Unable to retrieve notes: {error}", 503)
    finally:
        if client is not None:
            client.close()


@app.get("/api/notes/<note_id>")
def get_note(note_id):
    client = None
    try:
        UUID(note_id)
    except (AttributeError, TypeError, ValueError):
        return _json_error("id must be a valid UUID string.", 400)

    try:
        client, collection = _get_note_collection()
        note = collection.find_one({"id": note_id})
        if note is None:
            return _json_error("Note not found.", 404)
        return jsonify({"status": "ok", "note": _serialize_note(note)})
    except (PyMongoError, RuntimeError) as error:
        return _json_error(f"Unable to retrieve note: {error}", 503)
    finally:
        if client is not None:
            client.close()


@app.post("/api/notes")
def create_note():
    client = None
    try:
        payload = request.get_json(silent=True)
        _parse_note_payload(payload, require_id=True)
        note = {
            "id": payload["id"],
            "title": payload["title"],
            "content": payload["content"],
            "version": payload.get("version", 1),
            "updated_at": payload.get("updated_at", _utc_timestamp()),
            "is_deleted": payload.get("is_deleted", False),
        }
        client, collection = _get_note_collection()
        collection.insert_one(note)
        return jsonify({"status": "ok", "note": _serialize_note(note)}), 201
    except ValueError as error:
        return _json_error(str(error), 400)
    except DuplicateKeyError:
        return _json_error("A note with this id already exists.", 409)
    except (PyMongoError, RuntimeError) as error:
        return _json_error(f"Unable to create note: {error}", 503)
    finally:
        if client is not None:
            client.close()


@app.put("/api/notes/<note_id>")
def update_note(note_id):
    client = None
    try:
        UUID(note_id)
    except (AttributeError, TypeError, ValueError):
        return _json_error("id must be a valid UUID string.", 400)

    try:
        payload = request.get_json(silent=True)
        _parse_note_payload(payload, require_id=False)
        client, collection = _get_note_collection()
        existing = collection.find_one({"id": note_id})
        if existing is None:
            return _json_error("Note not found.", 404)

        updated_note = {
            "id": note_id,
            "title": payload["title"],
            "content": payload["content"],
            "version": existing["version"] + 1,
            "updated_at": _utc_timestamp(),
            "is_deleted": payload.get("is_deleted", existing["is_deleted"]),
        }
        collection.replace_one({"id": note_id}, updated_note)
        return jsonify({"status": "ok", "note": _serialize_note(updated_note)})
    except ValueError as error:
        return _json_error(str(error), 400)
    except (PyMongoError, RuntimeError) as error:
        return _json_error(f"Unable to update note: {error}", 503)
    finally:
        if client is not None:
            client.close()


@app.delete("/api/notes/<note_id>")
def delete_note(note_id):
    client = None
    try:
        UUID(note_id)
    except (AttributeError, TypeError, ValueError):
        return _json_error("id must be a valid UUID string.", 400)

    try:
        client, collection = _get_note_collection()
        existing = collection.find_one({"id": note_id})
        if existing is None:
            return _json_error("Note not found.", 404)

        deleted_note = {
            **existing,
            "version": existing["version"] + 1,
            "updated_at": _utc_timestamp(),
            "is_deleted": True,
        }
        collection.replace_one({"id": note_id}, deleted_note)
        return jsonify({"status": "ok", "note": _serialize_note(deleted_note)})
    except (PyMongoError, RuntimeError) as error:
        return _json_error(f"Unable to delete note: {error}", 503)
    finally:
        if client is not None:
            client.close()


if __name__ == "__main__":
    port = int(os.getenv("PORT", "5000"))
    app.run(host="127.0.0.1", port=port, debug=False)
