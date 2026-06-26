import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';
import 'cache_service.dart';
import 'sync_service.dart';

/// Background daily product updater
/// - Nightly: downloads full catalog from our API at user's chosen time
/// - Daily: updates details/prices/stock for popular items (≥ review threshold)
class BackgroundUpdater {
  static const _lastRunKey = 'daily_update_last_run';
  static const _reviewThresholdKey = 'daily_review_threshold';

  /// Called on app launch — checks if nightly sync is due.
  /// Downloads latest catalog from our API if within the sync window.
  static Future<bool> syncCatalogIfScheduled() async {
    try {
      final syncHour = await CacheService.getSyncHour();
      if (syncHour == -1) return false; // Manual only

      final lastSync = await CacheService.getLastSync();
      final now = DateTime.now();

      // Sync if current hour matches scheduled hour AND last sync > 20h ago
      if (now.hour != syncHour) return false;

      if (lastSync != null && now.difference(lastSync).inHours < 20) {
        return false;
      }

      print('[SYNC] Running nightly catalog sync ($syncHour:00)');
      final updated = await DatabaseService.instance.checkRemoteDb();
      if (updated) {
        await CacheService.setLastSync(now);
        print('[SYNC] Catalog updated');
      }

      // Keep WorkManager task in sync with user's preference
      await SyncService.schedule(hour: syncHour);

      return updated;
    } catch (e) {
      print('[SYNC] Error: $e');
      return false;
    }
  }

  static Future<void> checkAndRun({
    bool force = false,
    void Function(int done, int total)? onProgress,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final lastRun = prefs.getString(_lastRunKey);
    final now = DateTime.now();

    // Run if never run or >22h since last run (or forced)
    if (!force && lastRun != null) {
      final last = DateTime.tryParse(lastRun);
      if (last != null && now.difference(last).inHours < 22) {
        print('[DAILY] Skipped — last run ${last.toString().substring(0, 16)}');
        return;
      }
    }

    print('[DAILY] Starting background update...');
    await prefs.setString(_lastRunKey, now.toIso8601String());

    try {
      final reviewThreshold = prefs.getInt(_reviewThresholdKey) ?? 100;
      final storeNo = await _getStoreNo();
      await _runUpdate(reviewThreshold, storeNo, prefs, onProgress);
    } catch (e) {
      print('[DAILY] Error: $e');
    }
  }

  static Future<void> _runUpdate(
    int threshold,
    String storeNo,
    SharedPreferences prefs,
    void Function(int done, int total)? onProgress,
  ) async {
    // All data comes from OUR API — no Dan Murphy's key in the app.
    // Our server holds the DM key and proxies requests safely.

    final dbService = DatabaseService.instance;
    if (!dbService.isReady) {
      print('[DAILY] SQLite not ready, skipping');
      return;
    }

    try {
      // Step 1: Get current version from our API
      final apiBase = await CacheService.getApiBaseUrl();
      final versionResp = await http
          .get(Uri.parse('$apiBase/api/db/version'))
          .timeout(const Duration(seconds: 10));

      if (versionResp.statusCode != 200) {
        print('[DAILY] API version check failed');
        return;
      }

      final versionData = json.decode(versionResp.body) as Map<String, dynamic>;
      final remoteVersion = versionData['version'] ?? '';

      // Step 2: Get diff since last known version (small payload)
      final lastVersion = prefs.getString('db_version') ?? '';
      final diffResp = await http
          .get(Uri.parse('$apiBase/api/db/diff?since=$lastVersion'))
          .timeout(const Duration(seconds: 60));

      if (diffResp.statusCode == 200) {
        final diff = json.decode(diffResp.body) as Map<String, dynamic>;
        final products = diff['products'] as List<dynamic>? ?? [];
        final removed = diff['removed'] as List<dynamic>? ?? [];

        // Step 3: Apply diff to local SQLite
        for (final p in products) {
          await dbService.upsertProduct(
            p['stockcode']?.toString() ?? '',
            p as Map<String, dynamic>,
          );
        }

        for (final code in removed) {
          await dbService.removeProduct(code.toString());
        }

        onProgress?.call(products.length, products.length);
        await prefs.setString('db_version', remoteVersion.toString());
        print('[DAILY] Diff applied: +${products.length} -${removed.length}');
      } else if (diffResp.statusCode == 404) {
        // No diff available — download full DB
        print('[DAILY] No diff, downloading full DB...');
        await DatabaseService.instance.checkRemoteDb();
        await prefs.setString('db_version', remoteVersion.toString());
      }
    } catch (e) {
      print('[DAILY] Update error: $e');
    }
  }

  static Future<String> _getStoreNo() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('store_no') ?? '6176';
  }

  static Future<int> getReviewThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_reviewThresholdKey) ?? 100;
  }

  static Future<void> setReviewThreshold(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_reviewThresholdKey, value);
  }

  static Future<DateTime?> getLastRun() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_lastRunKey);
    return s != null ? DateTime.tryParse(s) : null;
  }

  /// Estimate how many products in local DB
  static Future<int> estimateProductCount(int threshold) async {
    if (!DatabaseService.instance.isReady) return 0;
    final r = await DatabaseService.instance.db.rawQuery(
      'SELECT COUNT(*) as c FROM products',
    );
    return (r.first['c'] as int?) ?? 0;
  }
}
