import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'cache_service.dart';
import 'database_service.dart';

const _taskName = 'nightly_catalog_sync';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final syncHour = prefs.getInt('sync_time') ?? 2;
      final now = DateTime.now();

      // Only run within +/- 1 hour of scheduled time
      if (syncHour >= 0) {
        final diff = (now.hour - syncHour).abs();
        if (diff > 1 && !(syncHour == 0 && now.hour == 23)) {
          return true;
        }
      }

      // Check WiFi
      try {
        final result = await InternetAddress.lookup('mydans.calvfletch.dev');
        if (result.isEmpty) return true;
      } catch (_) {
        return true;
      }

      // Get remote version
      final versionResp = await http
          .get(Uri.parse('https://mydans.calvfletch.dev/api/db/version'))
          .timeout(const Duration(seconds: 30));

      if (versionResp.statusCode != 200) return true;

      final versionData = json.decode(versionResp.body) as Map<String, dynamic>;
      final remoteVersion = versionData['version'] ?? '';

      // Try diff first
      final lastVersion = prefs.getString('db_version') ?? '';
      final diffResp = await http
          .get(
            Uri.parse(
              'https://mydans.calvfletch.dev/api/db/diff?since=$lastVersion',
            ),
          )
          .timeout(const Duration(seconds: 60));

      if (diffResp.statusCode == 200) {
        final diff = json.decode(diffResp.body) as Map<String, dynamic>;
        final products = diff['products'] as List<dynamic>? ?? [];
        final removed = diff['removed'] as List<dynamic>? ?? [];

        for (final p in products) {
          await DatabaseService.instance.upsertProduct(
            p['stockcode']?.toString() ?? '',
            p as Map<String, dynamic>,
          );
        }

        for (final code in removed) {
          await DatabaseService.instance.removeProduct(code.toString());
        }

        await prefs.setString('db_version', remoteVersion);
        print('[SYNC] Diff applied: +${products.length} -${removed.length}');
      } else {
        // Fall back to full download
        await DatabaseService.instance.checkRemoteDb();
        await prefs.setString('db_version', remoteVersion);
        print('[SYNC] Full download completed');
      }

      await CacheService.setLastSync(DateTime.now());
    } catch (e) {
      print('[SYNC] Error: $e');
    }
    return true;
  });
}

class SyncService {
  static Future<void> init() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: kDebugMode,
    );
  }

  static Future<void> schedule({int? hour}) async {
    final h = hour ?? await CacheService.getSyncHour();
    if (h < 0) {
      // Manual only — cancel any existing task
      await Workmanager().cancelByUniqueName(_taskName);
      print('[SYNC] Cancelled (manual only)');
      return;
    }

    // Calculate delay to next occurrence
    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day, h);
    if (next.isBefore(now)) next = next.add(const Duration(days: 1));
    final initialDelay = next.difference(now);

    await Workmanager().registerPeriodicTask(
      _taskName,
      _taskName,
      frequency: const Duration(hours: 24),
      initialDelay: initialDelay,
      constraints: Constraints(networkType: NetworkType.unmetered),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
    print('[SYNC] Scheduled for $h:00 daily (WiFi only)');
  }
}
