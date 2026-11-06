import os

from dotenv import load_dotenv
from pymongo import MongoClient
from pymongo.errors import PyMongoError

load_dotenv()


def get_mongodb_client() -> MongoClient:
    """Create a MongoDB client using environment configuration."""
    mongodb_uri = os.getenv("MONGODB_URI")
    if not mongodb_uri:
        raise RuntimeError("MONGODB_URI is not configured.")

    return MongoClient(mongodb_uri, serverSelectionTimeoutMS=5000)


def check_mongodb_connection() -> None:
    """Verify that MongoDB responds to a ping."""
    client = get_mongodb_client()
    try:
        client.admin.command("ping")
    except PyMongoError:
        raise
    finally:
        client.close()
