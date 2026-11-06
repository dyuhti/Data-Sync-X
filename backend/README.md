# Data Sync X backend

## Configuration

Copy `.env.example` to `.env` and set `MONGODB_URI` to the private MongoDB
Atlas connection string. Set `MONGODB_DATABASE` to the database name. For the
two-emulator validation demonstration, it must be
`datasyncx_phase8_e2e_validation`; do not point the demonstration backend at a
production database. Both emulators must use the same API instance. The
`.env` file is ignored by git and must not be committed.

## Start the API

From the repository root:

```powershell
python -m venv backend\venv
backend\venv\Scripts\Activate.ps1
pip install -r backend\requirements.txt
python backend\app.py
```

The API listens on port `5000` on all interfaces by default so Android
emulators can reach the host through `http://10.0.2.2:5000`. Set `HOST` or
`PORT` in `.env` to override the bind address or port. Binding to all
interfaces may expose the development API to other devices on your network;
use a trusted network and firewall as appropriate.

After starting the API, verify it responds at `http://127.0.0.1:5000/health`.
The Android emulator uses `http://10.0.2.2:5000/health` to reach the same API.

## Endpoints

- `GET /health` checks that the Flask application is running.
- `GET /health/database` checks the MongoDB connection.
- `GET /api/notes` returns all notes, including soft-deleted notes.
- `GET /api/notes/<id>` returns one note.
- `POST /api/notes` creates a note with `id`, `title`, and `content`. Retrying
  an identical request is idempotent. Reusing an ID with different data returns
  HTTP 409 with conflict type `DUPLICATE_INSERT`.
- `PUT /api/notes/<id>` updates a note and increments its version. The JSON
  body must include `base_version`, the version read by the offline client.
- `DELETE /api/notes/<id>` accepts a JSON body containing `base_version` and
  performs a version-checked soft delete.

Updates and soft deletes use an atomic MongoDB compare-and-swap on the note id,
base version, and deletion state. A concurrent change therefore cannot pass a
stale read and silently overwrite the winning version.

Version conflicts return HTTP 409 and a response shaped like:

```json
{
  "status": "conflict",
  "conflict_type": "UPDATE_UPDATE",
  "record_id": "note-uuid",
  "local_version": 2,
  "remote_version": 2,
  "local_payload": {},
  "remote_payload": {},
  "operation": "UPDATE"
}
```

`conflict_type` is `UPDATE_UPDATE` for a stale update against a live note,
`UPDATE_DELETE` when the remote note is deleted or a delete is stale, and
`DUPLICATE_INSERT` when a create reuses an existing ID with different data.

The `notes` collection is created by MongoDB on first insert. The API ensures
that `id` has a unique index whenever it accesses the collection.
