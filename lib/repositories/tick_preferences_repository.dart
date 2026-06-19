import 'package:shared_preferences/shared_preferences.dart';

/// Persists tick counts written by the iOS background fetch handler.
class TickPreferencesRepository {
  const TickPreferencesRepository();
  static const String tickCountKey = 'tick-count';
  static const String tickBackgroundCountKey = 'tick-background-count';
  static const String lastBackgroundFetchKey = 'last-background-fetch-at';

  Future<void> saveTickCounts({
    required int tickCount,
    required int tickBackgroundCount,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(tickCountKey, tickCount);
    await prefs.setInt(tickBackgroundCountKey, tickBackgroundCount);
    await prefs.setString(
      lastBackgroundFetchKey,
      DateTime.now().toIso8601String(),
    );
  }

  Future<({int tickCount, int tickBackgroundCount, String? lastFetchAt})>
  loadTickCounts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    return (
      tickCount: prefs.getInt(tickCountKey) ?? 0,
      tickBackgroundCount: prefs.getInt(tickBackgroundCountKey) ?? 0,
      lastFetchAt: prefs.getString(lastBackgroundFetchKey),
    );
  }
}
