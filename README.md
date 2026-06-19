# Flutter Background Service Use Case

A Flutter sample app demonstrating long-running background work with [`flutter_background_service`](https://pub.dev/packages/flutter_background_service). It runs a periodic tick loop while the app is active, persists data from iOS background fetch, and exposes start/stop/ping controls from the UI.

---

## When to Use This Approach

Use a background service when your app needs work to continue **outside the UI isolate** — for example syncing data, maintaining a socket connection, or running a periodic task while the user is not interacting with the screen.

| Use case | Android (`flutter_background_service`) | iOS (`flutter_background_service_ios`) |
|----------|----------------------------------------|----------------------------------------|
| Continuous work while app is open or minimized | Foreground service with persistent notification | `onForeground` handler while app process is alive |
| Short periodic sync when app is closed | Possible with `isForegroundMode: false` + battery optimization disabled (unreliable on some OEMs) | `onBackground` via Background Fetch (~15 min intervals, ~30 s runtime) |
| Real-time location tracking | Use `AndroidForegroundType.location` + location permissions | Use Core Location background modes instead |
| Push-driven updates | Prefer FCM + WorkManager for deferrable jobs | Prefer APNs silent push or BGAppRefreshTask |
| Music / navigation / calls | Use typed foreground service (`mediaPlayback`, `location`, etc.) | Use Audio, VoIP, or location background modes |

**Good fits for this plugin**

- Foreground data sync or socket keep-alive on Android (with a visible notification).
- Running Dart code in a separate isolate while the app is in the foreground or recently backgrounded.
- Occasional background refresh on iOS (fetch new data, update local cache, schedule notifications).

**Poor fits — use platform-specific alternatives instead**

- Guaranteed execution every few seconds while the app is fully closed (especially on iOS).
- Heavy CPU or network work without user-visible justification (App Store / Play policy risk).
- Replacing push notifications, alarm managers, or system schedulers for time-critical tasks.

---

## Architecture in This Project

```
main.dart          → UI isolate; start/stop service, listen to events
bg_service.dart    → Service configuration and isolate entry points
repositories/      → SharedPreferences persistence (used by iOS background fetch)
```

- **Android:** `_onStart` runs an infinite 1-second tick loop inside a **foreground service** (`isForegroundMode: true`, type `dataSync`).
- **iOS:** `_onStart` runs via `onForeground` while the app process is active; `_onIosBackground` runs via Background Fetch when the system grants a window.
- UI and service isolates **do not share memory**. Communication uses `invoke()` / `on()`.

---

## Android Configuration

### Manifest permissions and service declaration

`android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<service
    android:name="id.flutter.flutter_background_service.BackgroundService"
    android:foregroundServiceType="dataSync" />
```

| Setting | Value in this project | Notes |
|---------|----------------------|-------|
| `foregroundServiceType` | `dataSync` | Required on Android 14+ (SDK 34). Must match `AndroidForegroundType` in Dart. |
| `FOREGROUND_SERVICE_*` permission | `DATA_SYNC` | Must match the service type. Grant runtime notification permission on Android 13+. |
| Notification channel | `app_foreground_service` | Shown while the foreground service runs. |
| Notification ID | `888` | Used for the initial foreground notification. |

### Dart configuration

`lib/bg_service.dart`:

```dart
androidConfiguration: AndroidConfiguration(
  onStart: _onStart,
  autoStart: false,
  isForegroundMode: true,
  notificationChannelId: 'app_foreground_service',
  initialNotificationTitle: 'Background Service',
  initialNotificationContent: 'Initializing',
  foregroundServiceNotificationId: 888,
  foregroundServiceTypes: const [AndroidForegroundType.dataSync],
),
```

### Android limitations

- **Foreground notification is mandatory** when `isForegroundMode: true`. Android policy requires a visible notification for ongoing background work.
- **Permissions before start:** All required permissions (including `POST_NOTIFICATIONS` on API 33+) must be granted **before** calling `startService()`.
- **Battery optimization:** Some manufacturers (Xiaomi MIUI, Huawei, Samsung, etc.) aggressively kill background processes. Users may need to disable battery optimization for reliable behavior.
- **Release builds:** Entry points must be annotated with `@pragma('vm:entry-point')` or the service will not run in release mode.
- **No shared state with UI:** Use `invoke` / `on`, files, or a repository layer (e.g. SharedPreferences) to pass data between isolates.
- **Background without notification:** Setting `isForegroundMode: false` can keep work running after the app is closed, but it is less reliable and still subject to OEM battery policies. Test on real devices.
- **Service types:** Pick the correct `foregroundServiceType` for your use case. Misdeclaring types can cause crashes on Android 14+ or Play Store rejection.

### Optional Android customizations

- Add `res/drawable-*/ic_bg_service_small.png` (or vector in `drawable-anydpi-v24`) to customize the notification icon.
- Use `flutter_local_notifications` for rich, updatable foreground notifications inside `_onStart`.

---

## iOS Configuration

### Info.plist

`ios/Runner/Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
</array>

<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>dev.flutter.background.refresh</string>
</array>
```

| Key | Purpose |
|-----|---------|
| `UIBackgroundModes` → `fetch` | Enables Background Fetch capability. |
| `BGTaskSchedulerPermittedIdentifiers` | Required on iOS 13+ for `BGTaskScheduler`-based refresh. |

### AppDelegate

`ios/Runner/AppDelegate.swift`:

```swift
import flutter_background_service_ios

SwiftFlutterBackgroundServicePlugin.taskIdentifier = "dev.flutter.background.refresh"
```

The task identifier **must match** the value in `BGTaskSchedulerPermittedIdentifiers`.

### Xcode capability (recommended)

In Xcode → **Runner** target → **Signing & Capabilities**, add **Background Modes** and enable **Background fetch**. This aligns with the `fetch` entry in `Info.plist`.

### Dart configuration

`lib/bg_service.dart`:

```dart
iosConfiguration: IosConfiguration(
  autoStart: false,
  onForeground: _onStart,
  onBackground: _onIosBackground,
),
```

- **`onForeground`:** Same tick loop as Android while the iOS app process is running (foreground or suspended briefly).
- **`onBackground`:** Called by the system during a Background Fetch window. This project saves tick counts via `TickPreferencesRepository` and returns `true` when finished.

### iOS limitations

- **No true long-running service.** iOS suspends apps quickly in the background. There is no Android-equivalent always-on foreground service.
- **Background Fetch timing:** Intervals are **system-controlled**, typically **no faster than ~15 minutes**, and each run lasts roughly **15–30 seconds**. You cannot force a fixed schedule.
- **Unpredictable execution:** Fetch frequency depends on user behavior, battery, and system heuristics. Treat it as best-effort, not guaranteed.
- **App Store scrutiny:** Background modes must match real functionality declared in review notes. Do not enable `fetch` without actual periodic sync work.
- **Release builds:** Background entry points require `@pragma('vm:entry-point')` on `_onIosBackground` and `_onStart`.
- **Plugin registrant:** Call `DartPluginRegistrant.ensureInitialized()` (and `WidgetsFlutterBinding.ensureInitialized()` in background fetch) before using plugins in the background isolate.

---

## Platform Comparison

| | Android | iOS |
|---|---------|-----|
| Continuous background work | Yes, via foreground service + notification | No — only while app process is alive (`onForeground`) |
| Work when app is closed | Partial — foreground service or `isForegroundMode: false` (device-dependent) | Short periodic windows via Background Fetch |
| Minimum interval | ~1 s (your loop; subject to Doze) | ~15 min (system decides) |
| User-visible indicator | Persistent notification (foreground mode) | None for Background Fetch |
| Reliable on all devices | No — OEM battery savers vary | No — system schedules fetch opportunistically |

---

## Getting Started

```bash
flutter pub get
flutter run
```

1. Tap **Start Service** to launch the background isolate.
2. Observe **Tick Count** updating every second (Android foreground / iOS while app is active).
3. On iOS, background fetch updates **Saved Tick Background Count** when the system runs `_onIosBackground`; reload values after returning to the app.
4. Use **Ping Service** to verify UI ↔ isolate messaging.

For release testing:

```bash
flutter run --release
```

Background isolates do not work correctly in debug hot-reload scenarios; always validate in profile or release on physical devices.

---

## Dependencies

| Package | Role |
|---------|------|
| `flutter_background_service` | Core service API and Android implementation |
| `flutter_background_service_ios` | iOS Background Fetch integration |
| `shared_preferences` | Persisting tick data from the iOS background handler |

---

## References

- [flutter_background_service on pub.dev](https://pub.dev/packages/flutter_background_service)
- [Android foreground service types (Android 14+)](https://developer.android.com/about/versions/14/changes/fgs-types-required)
- [Apple Background Fetch documentation](https://developer.apple.com/documentation/uikit/app_and_environment/scenes/preparing_your_ui_to_run_in_the_background/updating_your_app_with_background_app_refresh)
- [Android background work overview](https://developer.android.com/develop/background-work/services)
