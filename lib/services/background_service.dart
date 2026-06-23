import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';

/// Background daily product updater
/// - Runs on app launch if >24h since last run
/// - Finds new products in catalog
/// - Updates details/prices/stock for popular items (≥ review threshold)
class BackgroundUpdater {
  static const _lastRunKey = 'daily_update_last_run';
  static const _reviewThresholdKey = 'daily_review_threshold';

  static Future<void> checkAndRun() async {
    final prefs = await SharedPreferences.getInstance();
    final lastRun = prefs.getString(_lastRunKey);
    final now = DateTime.now();

    // Run if never run or >22h since last run
    if (lastRun != null) {
      final last = DateTime.tryParse(lastRun);
      if (last != null && now.difference(last).inHours < 22) {
        print('[DAILY] Skipped — last run ${last.toString().substring(0, 16)}');
        return;
      }
    }

    print('[DAILY] Starting background update...');
    await prefs.setString(_lastRunKey, now.toIso8601String());

    try {
      final reviewThreshold = prefs.getInt(_reviewThresholdKey) ?? 300;
      final storeNo = await _getStoreNo();
      await _runUpdate(reviewThreshold, storeNo, prefs);
    } catch (e) {
      print('[DAILY] Error: $e');
    }
  }

  static Future<void> _runUpdate(int threshold, String storeNo, SharedPreferences prefs) async {
    final headers = {
      'Ocp-Apim-Subscription-Key': 'REDACTED3b914654a250e79d62250776',
      'User-Agent': 'DanMurphy/10.1.1',
      'Content-Type': 'application/json',
    };

    // Load existing cache
    final cacheRaw = prefs.getString('product_cache') ?? '{}';
    final Map<String, dynamic> cache = json.decode(cacheRaw) as Map<String, dynamic>;
    print('[DAILY] Existing cache: ${cache.length} products');

    // Step 1: Fetch current catalog codes
    final currentCodes = <String>{};
    for (var page = 1; page <= 80; page++) {
      try {
        final r = await http.post(
          Uri.parse('https://apiservices.danmurphys.com.au/cmpt/api/v2/AdvertisedOffers/Products'),
          headers: headers,
          body: json.encode({'PageNumber': page, 'PageSize': 50}),
        );
        if (r.statusCode != 200) break;
        final data = json.decode(r.body) as Map<String, dynamic>;
        final products = data['products'] as List<dynamic>? ?? [];
        if (products.isEmpty) break;
        for (final p in products) {
          currentCodes.add((p['id'] ?? '').toString());
        }
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (_) { break; }
    }
    print('[DAILY] Catalog: ${currentCodes.length} codes');

    // Step 2: Find new codes + popular codes
    final newCodes = currentCodes.where((c) => !cache.containsKey(c)).toList();
    final popularCodes = <String>[];
    for (final entry in cache.entries) {
      final p = entry.value as Map<String, dynamic>;
      final reviews = p['totalReviewCount'] as int? ?? 0;
      if (reviews >= threshold && currentCodes.contains(entry.key)) {
        popularCodes.add(entry.key);
      }
    }
    print('[DAILY] New: ${newCodes.length}, Popular: ${popularCodes.length}');

    // Step 3: Fetch details for new + popular
    final toFetch = <String>{...newCodes, ...popularCodes}.toList();
    var fetched = 0;

    for (final code in toFetch) {
      try {
        final r = await http.get(
          Uri.parse('https://api.danmurphys.com.au/apis/ui/Product/$code?StoreNo=$storeNo'),
          headers: headers,
        );
        if (r.statusCode == 200) {
          final data = json.decode(r.body) as Map<String, dynamic>;
          final products = data['Products'] as List<dynamic>?;
          if (products != null && products.isNotEmpty) {
            final p = products[0] as Map<String, dynamic>;
            final additionalDetails = (p['AdditionalDetails'] as List<dynamic>?) ?? [];
            String ad(String n) => (additionalDetails.firstWhere((d) => d['Name'] == n, orElse: () => {'Value': ''})['Value'] ?? '').toString();

            final priceMap = p['Prices'] as Map<String, dynamic>? ?? {};
            final prices = <Map<String, dynamic>>[];
            for (final entry in priceMap.entries) {
              final pd = entry.value as Map<String, dynamic>?;
              if (pd != null) prices.add({
                'type': entry.key,
                'message': '${pd['Message'] ?? ''}',
                'value': (pd['Value'] ?? 0).toDouble(),
                'preText': '${pd['PreText'] ?? ''}',
                'isMemberOffer': pd['IsMemberOffer'] == true,
                'packType': '${pd['PackType'] ?? ''}',
                'beforePromotion': (pd['BeforePromotion'] ?? 0).toDouble(),
                'afterPromotion': (pd['AfterPromotion'] ?? 0).toDouble(),
              });
            }

            final existing = cache[code] as Map<String, dynamic>?;
            cache[code] = {
              'stockcode': '${p['Stockcode'] ?? code}',
              'title': ad('webtitle'),
              'brand': ad('webbrandname'),
              'description': '${p['Description'] ?? ''}',
              'richDescription': '${p['RichDescription'] ?? ''}',
              'packageSize': ad('webliquorsize'),
              'alcoholVolume': ad('webalcoholpercentage'),
              'varietal': ad('varietal'),
              'region': ad('webregionoforigin'),
              'state': ad('webstateoforigin'),
              'country': ad('countryoforigin'),
              'vintage': ad('webvintagecurrent'),
              'closure': ad('webbottleclosure'),
              'standardDrinks': ad('standarddrinks'),
              'wineBody': ad('webwinebody'),
              'wineSweetness': ad('webwinestyle'),
              'averageRating': double.tryParse(ad('webaverageproductrating')),
              'totalReviewCount': int.tryParse(ad('webtotalreviewcount')) ?? 0,
              'smallImageUrl': '',
              'mediumImageUrl': '',
              'largeImageUrl': '',
              'stockOnHand': p['StockOnHand'] ?? 0,
              'isPurchasable': p['IsPurchasable'] == true,
              'categories': ((p['Categories'] as List<dynamic>?)?.map((c) => '${c['Name'] ?? ''}').toList() ?? []),
              'prices': prices,
              'firstSeen': existing?['firstSeen'] ?? DateTime.now().toIso8601String(),
              'lastUpdated': DateTime.now().toIso8601String(),
            };
            fetched++;
          }
        } else if (r.statusCode == 429) {
          await Future.delayed(const Duration(seconds: 30));
        }
      } catch (_) {}

      // Rate limit: 2 req/sec
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Step 4: Save
    await prefs.setString('product_cache', json.encode(cache));
    print('[DAILY] Done. Fetched: $fetched, Cache: ${cache.length} products');
  }

  static Future<String> _getStoreNo() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('store_no') ?? '6176';
  }

  static Future<int> getReviewThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_reviewThresholdKey) ?? 300;
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

  /// Estimate how many cached products have ≥N reviews
  static Future<int> estimateProductCount(int threshold) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheRaw = prefs.getString('product_cache') ?? '{}';
    final Map<String, dynamic> cache = json.decode(cacheRaw) as Map<String, dynamic>;
    int count = 0;
    for (final entry in cache.values) {
      final p = entry as Map<String, dynamic>;
      final reviews = p['totalReviewCount'] as int? ?? 0;
      if (reviews >= threshold) count++;
    }
    return count;
  }
}
