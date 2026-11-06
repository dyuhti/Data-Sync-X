# Data Sync X

Data Sync X is an offline-first notes application built with Flutter and
Material 3.

## Current phase

Phase 2 is a frontend-only implementation. Notes and synchronization data are
mocked in memory and are not persisted between application restarts.

Implemented screens:

- Home dashboard with search, note cards, sync status, and add-note action.
- Create and edit note flow with validation and delete support.
- Synchronization dashboard with mock activity and conflict entry point.
- Conflict review UI with mock local/server versions and resolution choices.
- Settings with automatic sync and default conflict policy controls.

SQLite, MongoDB, Flask APIs, network monitoring, and conflict algorithms are
intentionally not included in this phase.

## Run and validate

```shell
flutter pub get
flutter analyze
flutter test
flutter run
```
