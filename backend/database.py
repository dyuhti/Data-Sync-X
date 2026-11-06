import os

from dotenv import load_dotenv
from pymongo import MongoClient
from pymongo.errors import PyMongoError

load_dotenv()

NOTES_COLLECTION = "notes"


def get_mongodb_client() -> MongoClient:
    """Create a MongoDB client using environment configuration."""
    mongodb_uri = os.getenv("MONGODB_URI")
    if not mongodb_uri:
        raise RuntimeError("MONGODB_URI is not configured.")

    return MongoClient(mongodb_uri, serverSelectionTimeoutMS=5000)


def get_notes_collection():
    """Return the notes collection and ensure its UUID index exists."""
    database_name = os.getenv("MONGODB_DATABASE")
    if not database_name:
        raise RuntimeError("MONGODB_DATABASE is not configured.")

    client = get_mongodb_client()
    collection = client[database_name][NOTES_COLLECTION]
    collection.create_index("id", unique=True, name="unique_note_id")
    return client, collection


def check_mongodb_connection() -> None:
    """Verify that MongoDB responds to a ping."""
    client = get_mongodb_client()
    try:
        client.admin.command("ping")
    except PyMongoError:
        raise
    finally:
        client.close()
