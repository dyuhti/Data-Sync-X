# Data Sync X

Data Sync X is an offline-first notes app built with Flutter and Material 3.
Notes and pending operations are stored locally in SQLite. **Sync now** first
downloads and merges remote notes, uploads eligible pending operations using
their `base_version`, and downloads again to include updates made during the
upload phase. A remote merge never replaces a note with pending local changes;
the backend rejects stale writes with HTTP 409 and the app stores the conflict
for review.

## Reproduce an unresolved conflict

1. Configure the Flask backend with the dedicated validation database
   `datasyncx_phase8_e2e_validation` (see the backend README), then start the
   API and confirm `http://127.0.0.1:5000/health` responds.
   The Android emulator reaches the host API at `http://10.0.2.2:5000`.
2. Run the app on two emulators.
3. On emulator A, create a note and tap **Sync now**.
4. On emulator B, tap **Sync now** and confirm the message says it downloaded
   a note. Open **Home** and search for the unique title you created.
5. Edit that exact note on both emulators. Do not sync either edit yet.
6. Tap **Sync now** on emulator A, wait for it to finish, then tap it on B.
7. On emulator B, open **Sync** → **Recent activity** → **Review detected
   note differences** to resolve the conflict.

Conflicts are created only when the second device submits an edit based on an
older version. If you sync one device before editing the note on the other,
the second device downloads the latest version and no conflict is expected.
Notes already saved on existing installs are retained; removing starter notes
from one device requires deleting them in the app and syncing that deletion.

Both devices must be connected to the same API. To configure the backend and
MongoDB, see [the backend README](../../backend/README.md).

For emulator instances `emulator-5556` and `emulator-5558`, use the same
`DATASYNC_API_BASE_URL` on both builds. The default Android-emulator address is
`http://10.0.2.2:5000`.

## Run and validate

```shell
flutter pub get
flutter analyze
flutter test
flutter run
```
