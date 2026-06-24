/// Daily product updater
/// - Finds new products added to Dan Murphy's catalog
/// - Updates prices for popular items (configurable review threshold)
/// - Run via Windows Task Scheduler or cron: dart run daily_scrape.dart
///
/// Config: daily_config.json
///   { "reviewThreshold": 300, "runTimeHour": 6, "storeNo": "6176" }
library;

import 'dart:convert';
import 'dart:io';

void main() async {
  final startTime = DateTime.now();
  print('[DAILY] ${startTime.toIso8601String()} — Starting daily update...');

  // Load config
  final configFile = File('daily_config.json');
  Map<String, dynamic> config = {
    'reviewThreshold': 300,
    'runTimeHour': 6,
    'storeNo': '6176',
  };
  if (configFile.existsSync()) {
    config = json.decode(configFile.readAsStringSync()) as Map<String, dynamic>;
    print(
      '[DAILY] Config loaded: reviewThreshold=${config['reviewThreshold']}, runTimeHour=${config['runTimeHour']}',
    );
  } else {
    print('[DAILY] No config found, using defaults. Creating config file...');
    configFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(config),
    );
  }

  final reviewThreshold = config['reviewThreshold'] as int;
  final storeNo = config['storeNo'] as String;

  final headers = {
    'Ocp-Apim-Subscription-Key': 'REDACTED3b914654a250e79d62250776',
    'User-Agent': 'DanMurphy/10.1.1',
    'Content-Type': 'application/json',
  };

  final httpClient = HttpClient();
  httpClient.connectionTimeout = const Duration(seconds: 15);

  // Load existing DB
  final dbFile = File('assets/init_db.json');
  final Map<String, Map<String, dynamic>> db = {};
  if (dbFile.existsSync()) {
    final existing =
        json.decode(dbFile.readAsStringSync()) as Map<String, dynamic>;
    for (final entry in existing.entries) {
      db[entry.key] = entry.value as Map<String, dynamic>;
    }
    print('[DAILY] Loaded ${db.length} existing products from DB');
  }

  // Step 1: Fetch current catalog codes
  print('[DAILY] Step 1: Fetching current catalog...');
  final currentCodes = <String>{};
  for (var page = 1; page <= 80; page++) {
    try {
      final uri = Uri.parse(
        'https://apiservices.danmurphys.com.au/cmpt/api/v2/AdvertisedOffers/Products',
      );
      final request = await httpClient.postUrl(uri);
      headers.forEach((k, v) => request.headers.set(k, v));
      request.write(json.encode({'PageNumber': page, 'PageSize': 50}));
      final response = await request.close();
      if (response.statusCode != 200) break;
      final body = await response.transform(utf8.decoder).join();
      final data = json.decode(body) as Map<String, dynamic>;
      final products = data['products'] as List<dynamic>? ?? [];
      if (products.isEmpty) break;
      for (final p in products) {
        currentCodes.add((p['id'] ?? '').toString());
      }
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      print('[DAILY] Catalog page $page failed: $e');
      break;
    }
  }
  print('[DAILY] Current catalog: ${currentCodes.length} codes');

  // Step 2: Find new products (in catalog but not in DB)
  final newCodes = currentCodes.where((c) => !db.containsKey(c)).toList();
  print('[DAILY] New products to fetch: ${newCodes.length}');

  // Step 3: Find popular products needing price update
  final popularCodes = <String>[];
  for (final entry in db.entries) {
    final reviewCount = entry.value['totalReviewCount'] as int? ?? 0;
    if (reviewCount >= reviewThreshold && currentCodes.contains(entry.key)) {
      popularCodes.add(entry.key);
    }
  }
  print(
    '[DAILY] Popular products (≥$reviewThreshold reviews): ${popularCodes.length}',
  );

  // Step 4: Fetch details for new + popular products
  final toFetch = <String>{...newCodes, ...popularCodes}.toList();
  var done = 0;
  var fetched = 0;
  var failed = 0;

  for (final code in toFetch) {
    try {
      final uri = Uri.parse(
        'https://api.danmurphys.com.au/apis/ui/Product/$code?StoreNo=$storeNo',
      );
      final request = await httpClient.getUrl(uri);
      headers.forEach((k, v) => request.headers.set(k, v));
      final response = await request.close();

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = json.decode(body) as Map<String, dynamic>;
        final products = data['Products'] as List<dynamic>?;
        if (products != null && products.isNotEmpty) {
          final p = products[0] as Map<String, dynamic>;
          final additionalDetails =
              (p['AdditionalDetails'] as List<dynamic>?) ?? [];
          String ad(String name) =>
              (additionalDetails.firstWhere(
                        (d) => d['Name'] == name,
                        orElse: () => {'Value': ''},
                      )['Value'] ??
                      '')
                  .toString();

          final priceMap = p['Prices'] as Map<String, dynamic>? ?? {};
          final priceList = <Map<String, dynamic>>[];
          for (final entry in priceMap.entries) {
            final pd = entry.value as Map<String, dynamic>?;
            if (pd != null) {
              priceList.add({
                'type': entry.key,
                'message': (pd['Message'] ?? '').toString(),
                'value': (pd['Value'] ?? 0).toDouble(),
                'preText': (pd['PreText'] ?? '').toString(),
                'isMemberOffer': pd['IsMemberOffer'] == true,
                'packType': (pd['PackType'] ?? '').toString(),
                'beforePromotion': (pd['BeforePromotion'] ?? 0).toDouble(),
                'afterPromotion': (pd['AfterPromotion'] ?? 0).toDouble(),
              });
            }
          }

          final reviewCount = int.tryParse(ad('webtotalreviewcount')) ?? 0;
          final existing = db[code];

          db[code] = {
            'stockcode': (p['Stockcode'] ?? code).toString(),
            'title': ad('webtitle'),
            'brand': ad('webbrandname'),
            'description': (p['Description'] ?? '').toString(),
            'richDescription': (p['RichDescription'] ?? '').toString(),
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
            'totalReviewCount': reviewCount,
            'smallImageUrl': '',
            'mediumImageUrl': '',
            'largeImageUrl': '',
            'categories':
                ((p['Categories'] as List<dynamic>?)
                    ?.map((c) => (c['Name'] ?? '').toString())
                    .toList() ??
                []),
            'prices': priceList,
            'firstSeen':
                existing?['firstSeen'] ?? DateTime.now().toIso8601String(),
            'lastUpdated': DateTime.now().toIso8601String(),
          };
          fetched++;
        }
      } else if (response.statusCode == 429 || response.statusCode == 403) {
        print('[DAILY] Blocked at $done/${toFetch.length}. Waiting 30s...');
        await Future.delayed(const Duration(seconds: 30));
      }
    } catch (e) {
      failed++;
    }

    done++;
    if (done % 50 == 0) {
      print(
        '[DAILY] $done/${toFetch.length} ($fetched fetched, $failed failed)',
      );
    }

    // Rate limit: 1 req/sec
    await Future.delayed(const Duration(seconds: 1));
  }

  // Step 5: Save updated DB
  print('[DAILY] Saving updated DB...');
  dbFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(db));
  print(
    '[DAILY] Done. DB: ${db.length} products. New: ${newCodes.length}, Updated: ${popularCodes.length}, Fetched: $fetched, Failed: $failed',
  );

  // Write log
  final elapsed = DateTime.now().difference(startTime);
  final logEntry =
      '${startTime.toIso8601String()} | New:${newCodes.length} Updated:${popularCodes.length} Fetched:$fetched Failed:$failed DB:${db.length} Duration:${elapsed.inMinutes}m\n';
  File('daily_scrape.log').writeAsStringSync(logEntry, mode: FileMode.append);

  httpClient.close();
}
