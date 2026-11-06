import os

from flask import Flask, jsonify
from flask_cors import CORS
from pymongo.errors import PyMongoError

from database import check_mongodb_connection

app = Flask(__name__)
CORS(app)


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


if __name__ == "__main__":
    port = int(os.getenv("PORT", "5000"))
    app.run(host="127.0.0.1", port=port, debug=False)
