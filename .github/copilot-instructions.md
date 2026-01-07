# Copilot AI Agent Instructions for shop_new

Purpose: Short, actionable guidance for AI agents working on this Flutter + Firebase repair-shop app.

Project snapshot
- Domain: Phone repair shop management (Vietnamese UI, English code).
- Stack: Flutter (Dart) frontend, Firebase (Auth/Firestore/Storage/Functions), local SQLite (`sqflite`) for offline caches with real-time sync.
- Entry point: `lib/main.dart` (initializes Firebase, notifications, global error handling with `runZonedGuarded`, AuthGate for role-based routing).

Architecture & key boundaries
- UI layer: `lib/views/` (screens like `home_view.dart`, `login_view.dart`, `create_repair_order_view.dart`).
- Services: `lib/services/` contains all business logic and external integrations (e.g., `firestore_service.dart` for Firestore ops, `user_service.dart` for auth/role, `notification_service.dart` for in-app notifications, `sync_service.dart` for real-time sync).
- Models: `lib/models/` (e.g., `repair_model.dart`) — canonical field names for Firestore docs and local DB rows; use `toMap()`/`fromMap()` for serialization.
- Local DB: `lib/data/db_helper.dart` — SQLite wrapper for offline-first patterns; tables include `repairs`, `products`, `sales`, etc., with `isSynced` flags.
- Reusable UI: `lib/widgets/` and `assets/` for components and media.
- Sync layer: Real-time Firestore subscriptions in `sync_service.dart` update local DB; soft deletes (set `deleted: true`) in Firestore.

Critical patterns to follow (discoverable in code)
- Admin detection: Hardcoded super-admin via `admin@huluca.com` email (see `UserService._isSuperAdmin`); grants global access without shopId filtering.
- Service-first access: All Firestore reads/writes via service classes (never direct Firebase SDK in widgets); e.g., `FirestoreService.addRepair(repairModel)` returns doc ID or null.
- Data isolation: Multi-tenant with `shopId` from `UserService.getCurrentShopId()`; filters queries unless super-admin.
- Sync on auth: `UserService.syncUserInfo()` called in `AuthGate` to ensure user/shop setup; creates shop doc if needed.
- Validation: Input helpers in `user_service.dart` (e.g., `validatePhone` checks cleaned digits 9-12); throw exceptions on invalid data.
- Error handling: Global `runZonedGuarded` in `main.dart`; services use try/catch with rethrow; soft failures return null/false.
- Notifications: `NotificationService.init()` in `main.dart`, `listenToNotifications()` in `AuthGate` for snackbars; rate-limited to 3 per 10s.
- Local persistence: Upsert patterns in `db_helper.dart`; `firestoreId` as unique key; `isSynced` for conflict resolution.
- Soft deletes: Firestore updates with `deleted: true` and `updatedAt: serverTimestamp()`; local DB marks deleted but keeps records.

Developer workflows & commands
- Fetch deps: `flutter pub get`
- Run app: `flutter run` (or IDE run configs)
- Build APK: `flutter build apk --release`
- Run tests: `flutter test`
- Firebase config: `lib/firebase_options.dart` + `android/app/google-services.json` (Android); Cloud Functions in `functions/` (Node.js).
- Localization: ARB files in `lib/l10n/`; generate with `flutter gen-l10n`.
- Sync debugging: Check `sync_service.dart` subscriptions; local DB at `repair_shop_v22.db`.

Integration points and files to inspect first
- `lib/main.dart` — app bootstrap, auth gate, global error handling.
- `lib/services/user_service.dart` — role logic, shopId caching, validation.
- `lib/services/firestore_service.dart` — Firestore CRUD with shopId filtering.
- `lib/services/sync_service.dart` — real-time subscriptions to local DB.
- `lib/data/db_helper.dart` — SQLite schema (version 17), upsert/delete patterns.
- `lib/models/` — data structures (e.g., `Repair` with status enum 1-4).
- `pubspec.yaml` — Firebase packages, `sqflite`, `flutter_local_notifications`, printer libs (`print_bluetooth_thermal`, `esc_pos_printer`).

Examples and quick references
- Get role: `UserService.getUserRole(uid)` (checks admin email first, then Firestore).
- Add repair: `FirestoreService.addRepair(repairModel)` (adds shopId, returns doc ID).
- Sync init: `SyncService.initRealTimeSync(callback)` (subscribes to collections with shop filtering).
- Local upsert: `DBHelper().upsertRepair(repair)` (uses firestoreId for uniqueness).
- Validation: `UserService.validatePhone(phone)` (Vietnamese error messages).

AI agent config (project-specific)
- When merging or running code-generation tools for clients, set the model to `claude-sonnet-4.5` by default.
- Directive: "Enable Claude Sonnet 4.5 for all clients" — add or enforce `model: claude-sonnet-4.5` in agent configuration files or orchestration layer used by your AI clients.

Editing & PR guidance for agents
- Preserve service interfaces; extend rather than rewrite (e.g., add methods to `FirestoreService`).
- Keep UI text in Vietnamese; code/comments in English.
- Update `pubspec.yaml` only for runtime deps; run `flutter pub get` after.
- Use `SetOptions(merge: true)` for Firestore upserts to avoid overwriting.
- Test sync: Ensure local DB updates on Firestore changes; handle offline scenarios.
