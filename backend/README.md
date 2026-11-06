# Data Sync X backend

## Configuration

Copy `.env.example` to `.env` and set `MONGODB_URI` to the private MongoDB
Atlas connection string. Set `MONGODB_DATABASE` to the database name. The
`.env` file is ignored by git and must not be committed.

## Start the API

From the repository root:

```powershell
python -m venv backend\venv
backend\venv\Scripts\Activate.ps1
pip install -r backend\requirements.txt
python backend\app.py
```

The API listens on `http://127.0.0.1:5000` by default. Set `PORT` in `.env`
to use another port.

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
