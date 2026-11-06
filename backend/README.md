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
- `POST /api/notes` creates a note with `id`, `title`, and `content`.
- `PUT /api/notes/<id>` updates a note and increments its version.
- `DELETE /api/notes/<id>` soft-deletes a note.

The `notes` collection is created by MongoDB on first insert. The API ensures
that `id` has a unique index whenever it accesses the collection.
