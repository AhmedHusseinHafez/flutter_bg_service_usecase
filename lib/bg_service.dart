import 'dart:developer';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_back_ground_service_usecase/repositories/tick_preferences_repository.dart';

/// Manages the background foreground service lifecycle.
@pragma('vm:entry-point')
class AppBackgroundService {
  AppBackgroundService._();

  static const String notificationChannelId = 'app_foreground_service';
  static const int foregroundServiceNotificationId = 888;
  static const String stopEvent = 'stopService';
  static const String appLifecycleEvent = 'appLifecycle';

  static final FlutterBackgroundService _service = FlutterBackgroundService();

  /// Configures platform handlers. Call from [main] before [runApp].
  static Future<void> initialize() async {
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: notificationChannelId,
        initialNotificationTitle: 'Background Service',
        initialNotificationContent: 'Initializing',
        foregroundServiceNotificationId: foregroundServiceNotificationId,
        foregroundServiceTypes: const [AndroidForegroundType.dataSync],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );
  }

  static Future<bool> isRunning() => _service.isRunning();

  static Future<void> start() => _service.startService();

  static void stop() => _service.invoke(stopEvent);

  static Stream<Map<String, dynamic>?> on(String method) => _service.on(method);

  static void invoke(String method, [Map<String, dynamic>? arguments]) =>
      _service.invoke(method, arguments);

  static void notifyAppLifecycle(AppLifecycleState state) {
    invoke(appLifecycleEvent, {'state': state.name});
  }

  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    const repository = TickPreferencesRepository();
    var lastSavedCount = -1;

    for (var i = 0; i < 1000; i++) {
      lastSavedCount = i;
      await repository.saveTickCounts(tickCount: i, tickBackgroundCount: i);

      service.invoke('tick', {'count': i, 'platform': 'ios-background-fetch'});
      service.invoke('tick-background', {
        'count': i,
        'platform': 'ios-background-fetch',
      });
      // await Future.delayed(const Duration(milliseconds: 100));
    }

    log(
      'iOS background fetch saved tick counts up to $lastSavedCount',
      name: 'AppBackgroundService',
    );
    return true;
  }

  @pragma('vm:entry-point')
  static void _onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    service.on(stopEvent).listen((_) {
      service.stopSelf();
    });

    // if (service is AndroidServiceInstance &&
    //     await service.isForegroundService()) {
    //   await service.setForegroundNotificationInfo(
    //     title: 'Background Service',
    //     content: 'Running',
    //   );
    // }
    service.on('ping').listen((event) {
      service.invoke('pong', {
        'message': 'alive',
        'ts': DateTime.now().toIso8601String(),
      });
    });

    // Periodic tick - proves the service is alive and well
    int count = 0;
    while (true) {
      await Future.delayed(const Duration(seconds: 1));
      count++;
      final tickEvent = {'count': count};
      service.invoke('tick', tickEvent);
    }
  }
}
