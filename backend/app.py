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


def _conflict_response(
    *,
    conflict_type,
    record_id,
    local_version,
    remote_version,
    local_payload,
    remote_payload,
    operation,
):
    return jsonify({
        "status": "conflict",
        "conflict_type": conflict_type,
        "record_id": record_id,
        "local_version": local_version,
        "remote_version": remote_version,
        "local_payload": local_payload,
        "remote_payload": remote_payload,
        "operation": operation,
    }), 409


def _require_base_version(payload):
    if not isinstance(payload, dict):
        raise ValueError("Request body must be a JSON object.")
    base_version = payload.get("base_version")
    if (
        not isinstance(base_version, int)
        or isinstance(base_version, bool)
        or base_version < 0
    ):
        raise ValueError("base_version must be a non-negative integer.")
    return base_version


def _local_version(payload, base_version):
    version = payload.get("version", base_version + 1)
    if isinstance(version, int) and not isinstance(version, bool):
        return version
    return base_version + 1


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
        existing = collection.find_one({"id": note["id"]})
        if existing is not None:
            existing_note = _serialize_note(existing)
            if existing_note == _serialize_note(note):
                return jsonify({"status": "ok", "note": existing_note})
            return _conflict_response(
                conflict_type="DUPLICATE_INSERT",
                record_id=note["id"],
                local_version=note["version"],
                remote_version=existing_note["version"],
                local_payload=_serialize_note(note),
                remote_payload=existing_note,
                operation="CREATE",
            )
        collection.insert_one(note)
        return jsonify({"status": "ok", "note": _serialize_note(note)}), 201
    except ValueError as error:
        return _json_error(str(error), 400)
    except DuplicateKeyError:
        existing = collection.find_one({"id": note["id"]})
        if existing is not None:
            existing_note = _serialize_note(existing)
            if existing_note == _serialize_note(note):
                return jsonify({"status": "ok", "note": existing_note})
            return _conflict_response(
                conflict_type="DUPLICATE_INSERT",
                record_id=note["id"],
                local_version=note["version"],
                remote_version=existing_note["version"],
                local_payload=_serialize_note(note),
                remote_payload=existing_note,
                operation="CREATE",
            )
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
        base_version = _require_base_version(payload)
        client, collection = _get_note_collection()
        existing = collection.find_one({"id": note_id})
        if existing is None:
            return _json_error("Note not found.", 404)
        remote_note = _serialize_note(existing)
        local_payload = {
            "id": note_id,
            "title": payload["title"],
            "content": payload["content"],
            "version": _local_version(payload, base_version),
            "updated_at": payload.get("updated_at", _utc_timestamp()),
            "is_deleted": payload.get("is_deleted", False),
            "base_version": base_version,
        }
        restoring_deleted = (
            existing.get("is_deleted", False)
            and payload.get("is_deleted") is False
            and base_version == existing["version"]
        )
        if existing.get("is_deleted", False) and not restoring_deleted:
            return _conflict_response(
                conflict_type="UPDATE_DELETE",
                record_id=note_id,
                local_version=local_payload["version"],
                remote_version=remote_note["version"],
                local_payload=local_payload,
                remote_payload=remote_note,
                operation="UPDATE",
            )
        if base_version != existing["version"]:
            return _conflict_response(
                conflict_type="UPDATE_UPDATE",
                record_id=note_id,
                local_version=local_payload["version"],
                remote_version=remote_note["version"],
                local_payload=local_payload,
                remote_payload=remote_note,
                operation="UPDATE",
            )

        updated_note = {
            "id": note_id,
            "title": payload["title"],
            "content": payload["content"],
            "version": existing["version"] + 1,
            "updated_at": _utc_timestamp(),
            "is_deleted": payload.get("is_deleted", existing["is_deleted"]),
        }
        result = collection.replace_one(
            {
                "id": note_id,
                "version": base_version,
                "is_deleted": existing.get("is_deleted", False),
            },
            updated_note,
        )
        if result.matched_count == 0:
            latest = collection.find_one({"id": note_id})
            if latest is None:
                return _json_error("Note not found.", 404)
            latest_note = _serialize_note(latest)
            return _conflict_response(
                conflict_type=(
                    "UPDATE_DELETE"
                    if latest_note["is_deleted"]
                    else "UPDATE_UPDATE"
                ),
                record_id=note_id,
                local_version=local_payload["version"],
                remote_version=latest_note["version"],
                local_payload=local_payload,
                remote_payload=latest_note,
                operation="UPDATE",
            )
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
        payload = request.get_json(silent=True)
        base_version = _require_base_version(payload)
        client, collection = _get_note_collection()
        existing = collection.find_one({"id": note_id})
        if existing is None:
            return _json_error("Note not found.", 404)
        remote_note = _serialize_note(existing)
        local_version = base_version + 1
        local_payload = {
            "id": note_id,
            "version": local_version,
            "base_version": base_version,
            "is_deleted": True,
        }
        if existing.get("is_deleted", False):
            return jsonify({"status": "ok", "note": remote_note})
        if base_version != existing["version"]:
            return _conflict_response(
                conflict_type="UPDATE_DELETE",
                record_id=note_id,
                local_version=local_version,
                remote_version=remote_note["version"],
                local_payload=local_payload,
                remote_payload=remote_note,
                operation="DELETE",
            )

        deleted_note = {
            **existing,
            "version": existing["version"] + 1,
            "updated_at": _utc_timestamp(),
            "is_deleted": True,
        }
        result = collection.replace_one(
            {
                "id": note_id,
                "version": base_version,
                "is_deleted": False,
            },
            deleted_note,
        )
        if result.matched_count == 0:
            latest = collection.find_one({"id": note_id})
            if latest is None:
                return _json_error("Note not found.", 404)
            latest_note = _serialize_note(latest)
            if latest_note["is_deleted"]:
                return jsonify({"status": "ok", "note": latest_note})
            return _conflict_response(
                conflict_type="UPDATE_DELETE",
                record_id=note_id,
                local_version=local_version,
                remote_version=latest_note["version"],
                local_payload=local_payload,
                remote_payload=latest_note,
                operation="DELETE",
            )
        return jsonify({"status": "ok", "note": _serialize_note(deleted_note)})
    except (PyMongoError, RuntimeError) as error:
        return _json_error(f"Unable to delete note: {error}", 503)
    finally:
        if client is not None:
            client.close()


if __name__ == "__main__":
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "5000"))
    app.run(host=host, port=port, debug=False)
