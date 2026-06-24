import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/product.dart';
import 'cache_service.dart';
import 'api_service.dart';
import 'database_service.dart';

/// Search engine over SQLite-backed product database.
/// Falls back to in-memory JSON if SQLite is empty.
class SearchService {
  static final Map<String, Product> _db = {};

  static Map<String, Product> get database => _db;
  static int get size => DatabaseService.instance.isReady
      ? DatabaseService.instance.count
      : _db.length;

  /// Load cached products on startup
  static Future<void> init() async {
    // If SQLite has data, use it (loaded by DatabaseService)
    if (DatabaseService.instance.isReady &&
        DatabaseService.instance.count > 0) {
      print(
        '[DB] SQLite ready with ${DatabaseService.instance.count} products',
      );
      return;
    }

    // Fallback: load bundled JSON into memory
    try {
      final jsonStr = await rootBundle.loadString('assets/init_db.json');
      final map = json.decode(jsonStr) as Map<String, dynamic>;
      for (final entry in map.entries) {
        _db[entry.key] = Product.fromOfferJson(
          entry.value as Map<String, dynamic>,
        );
      }
      print(
        '[DB] Loaded ${_db.length} products from bundled init DB (fallback)',
      );
    } catch (_) {
      print('[DB] No bundled init DB found');
    }

    final cached = await CacheService.loadProductDb();
    for (final entry in cached.entries) {
      _db.putIfAbsent(entry.key, () => entry.value);
    }
    print('[DB] Total local products: ${_db.length}');
  }

  /// Main search: two-phase — local instant, then web populates DB asynchronously.
  /// Pass [onUpdated] to get called when web results are cached (UI can re-query).
  static Future<List<Product>> search(
    String query, {
    void Function()? onUpdated,
  }) async {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return [];

    final useSqlite =
        DatabaseService.instance.isReady && DatabaseService.instance.count > 0;

    // Phase 1: Local search (instant — no waiting for web)
    List<Product> localResults;
    if (useSqlite) {
      localResults = await DatabaseService.instance.search(query);
    } else {
      localResults = _fuzzyMatch(trimmed);
    }

    // Phase 2: Background web search → cache to SQLite/memory → notify UI
    if (trimmed.length >= 2) {
      _fetchAndCache(query, trimmed, useSqlite).then((_) => onUpdated?.call());
    }

    return localResults.take(30).toList();
  }

  /// Background web fetch + cache (never blocks UI)
  static Future<void> _fetchAndCache(
    String query,
    String trimmed,
    bool useSqlite,
  ) async {
    try {
      final webResults = await ApiService.webSearch(
        query,
      ).timeout(const Duration(seconds: 8));
      if (webResults.isEmpty) return;
      for (final p in webResults) {
        _cacheProduct(p, useSqlite: useSqlite);
      }
    } catch (_) {}
  }

  /// Fuzzy match: n-gram overlap + prefix bonus + exact code match
  static List<Product> _fuzzyMatch(String query) {
    final results = <_ScoredProduct>[];

    for (final entry in _db.entries) {
      final p = entry.value;
      double score = 0;

      // Exact stock code match → highest priority
      if (p.stockcode == query) {
        score = 100;
      } else if (p.stockcode.startsWith(query)) {
        score = 80;
      }

      // Text matching (current title + previous titles for renamed products)
      final text =
          '${p.title} ${p.brand} ${p.stockcode} ${p.previousTitles.join(' ')}'
              .toLowerCase();

      // Exact word boundary match (e.g. "bin" matches "Penfolds Bin 389")
      final queryWords = query.split(RegExp(r'\s+'));
      for (final word in queryWords) {
        if (text.contains(word)) {
          score += 15;
          // Bonus for word-boundary match
          if (RegExp('\\b$word\\b').hasMatch(text)) {
            score += 10;
          }
          // Bonus if word starts title
          if (p.title.toLowerCase().startsWith(word)) {
            score += 5;
          }
        }
      }

      // N-gram overlap for typo tolerance (bigrams)
      final queryBigrams = _bigrams(query);
      final textBigrams = _bigrams(text);
      final overlap = queryBigrams
          .where((bg) => textBigrams.contains(bg))
          .length;
      if (queryBigrams.isNotEmpty) {
        score += (overlap / queryBigrams.length) * 20;
      }

      if (score > 0) {
        results.add(_ScoredProduct(p, score));
      }
    }

    // Sort by score descending, then by title
    results.sort((a, b) {
      final cmp = b.score.compareTo(a.score);
      if (cmp != 0) return cmp;
      return a.product.title.compareTo(b.product.title);
    });

    return results.map((r) => r.product).take(30).toList();
  }

  /// Generate character bigrams for fuzzy matching
  static Set<String> _bigrams(String s) {
    final result = <String>{};
    for (var i = 0; i < s.length - 1; i++) {
      result.add(s.substring(i, i + 2));
    }
    return result;
  }

  /// Cache a product — SQLite if ready, otherwise in-memory
  static void _cacheProduct(Product incoming, {bool useSqlite = false}) {
    if (useSqlite && DatabaseService.instance.isReady) {
      DatabaseService.instance.upsertProduct(
        incoming.stockcode,
        incoming.toOfferJson(),
      );
      return;
    }
    final existing = _db[incoming.stockcode];
    if (existing != null) {
      final prevTitles = List<String>.from(existing.previousTitles);

      // Track title changes
      if (incoming.title.isNotEmpty && incoming.title != existing.title) {
        if (!prevTitles.contains(existing.title)) {
          prevTitles.add(existing.title);
        }
      }

      // Track price changes
      final priceHist = List<PriceRecord>.from(existing.priceHistory);
      final singlePrice = incoming.prices
          .where((p) => p.type == 'singleprice')
          .firstOrNull;
      if (singlePrice != null && singlePrice.value > 0) {
        final lastRecord = priceHist.isNotEmpty ? priceHist.last : null;
        if (lastRecord == null || lastRecord.value != singlePrice.value) {
          priceHist.add(
            PriceRecord(
              date: DateTime.now(),
              value: singlePrice.value,
              type: 'singleprice',
            ),
          );
        }
      }

      _db[incoming.stockcode] = Product(
        stockcode: incoming.stockcode,
        title: incoming.title.isNotEmpty ? incoming.title : existing.title,
        brand: incoming.brand.isNotEmpty ? incoming.brand : existing.brand,
        description: incoming.description.isNotEmpty
            ? incoming.description
            : existing.description,
        richDescription: incoming.richDescription.isNotEmpty
            ? incoming.richDescription
            : existing.richDescription,
        packageSize: incoming.packageSize.isNotEmpty
            ? incoming.packageSize
            : existing.packageSize,
        alcoholVolume: incoming.alcoholVolume.isNotEmpty
            ? incoming.alcoholVolume
            : existing.alcoholVolume,
        varietal: incoming.varietal.isNotEmpty
            ? incoming.varietal
            : existing.varietal,
        region: incoming.region.isNotEmpty ? incoming.region : existing.region,
        state: incoming.state.isNotEmpty ? incoming.state : existing.state,
        country: incoming.country.isNotEmpty
            ? incoming.country
            : existing.country,
        vintage: incoming.vintage.isNotEmpty
            ? incoming.vintage
            : existing.vintage,
        closure: incoming.closure.isNotEmpty
            ? incoming.closure
            : existing.closure,
        standardDrinks: incoming.standardDrinks.isNotEmpty
            ? incoming.standardDrinks
            : existing.standardDrinks,
        wineBody: incoming.wineBody.isNotEmpty
            ? incoming.wineBody
            : existing.wineBody,
        wineSweetness: incoming.wineSweetness.isNotEmpty
            ? incoming.wineSweetness
            : existing.wineSweetness,
        averageRating: incoming.averageRating ?? existing.averageRating,
        totalReviewCount: incoming.totalReviewCount > 0
            ? incoming.totalReviewCount
            : existing.totalReviewCount,
        prices: incoming.prices.isNotEmpty ? incoming.prices : existing.prices,
        stockOnHand: incoming.stockOnHand,
        isPurchasable: incoming.isPurchasable,
        isOnSpecial: incoming.isOnSpecial,
        isMemberSpecial: incoming.isMemberSpecial,
        categories: incoming.categories.isNotEmpty
            ? incoming.categories
            : existing.categories,
        previousTitles: prevTitles,
        priceHistory: priceHist,
      );
    } else {
      _db[incoming.stockcode] = incoming;
    }
    CacheService.saveProductDb(_db);
  }

  /// Hydrate live data for a product. Skips API call if data is fresh.
  /// - Price/stock: refreshed if older than 5 minutes
  /// - All other fields: refreshed if older than 24 hours
  static Future<Product> hydrate(Product p, {String? storeNo}) async {
    final now = DateTime.now();
    final priceStale = p.lastPriceRefresh == null ||
        now.difference(p.lastPriceRefresh!).inMinutes >= 5;
    final detailStale = p.lastDetailRefresh == null ||
        now.difference(p.lastDetailRefresh!).inHours >= 24;

    if (!priceStale && !detailStale) return p; // fully fresh

    final live = await ApiService.getProduct(p.stockcode, storeNo: storeNo);
    if (live == null) return p;

    // Merge: only overwrite fields that are stale
    final merged = p.copyWith(
      stockOnHand: priceStale ? live.stockOnHand : null,
    );

    // Update the in-memory DB with the merged product
    // For simplicity, just replace with live + preserve timestamps
    final updated = Product(
      stockcode: live.stockcode,
      title: detailStale ? live.title : p.title,
      brand: detailStale ? live.brand : p.brand,
      description: detailStale ? live.description : p.description,
      richDescription: detailStale ? live.richDescription : p.richDescription,
      packageSize: detailStale ? live.packageSize : p.packageSize,
      alcoholVolume: detailStale ? live.alcoholVolume : p.alcoholVolume,
      varietal: detailStale ? live.varietal : p.varietal,
      region: detailStale ? live.region : p.region,
      state: detailStale ? live.state : p.state,
      country: detailStale ? live.country : p.country,
      vintage: detailStale ? live.vintage : p.vintage,
      closure: detailStale ? live.closure : p.closure,
      standardDrinks: detailStale ? live.standardDrinks : p.standardDrinks,
      wineBody: detailStale ? live.wineBody : p.wineBody,
      wineSweetness: detailStale ? live.wineSweetness : p.wineSweetness,
      averageRating: detailStale ? live.averageRating : p.averageRating,
      totalReviewCount: detailStale ? live.totalReviewCount : p.totalReviewCount,
      prices: priceStale ? live.prices : p.prices,
      stockOnHand: priceStale ? live.stockOnHand : p.stockOnHand,
      isPurchasable: priceStale ? live.isPurchasable : p.isPurchasable,
      isOnSpecial: priceStale ? live.isOnSpecial : p.isOnSpecial,
      isMemberSpecial: priceStale ? live.isMemberSpecial : p.isMemberSpecial,
      categories: detailStale ? live.categories : p.categories,
      previousTitles: p.previousTitles,
      priceHistory: p.priceHistory,
      firstSeen: p.firstSeen,
      lastPriceRefresh: priceStale ? now : p.lastPriceRefresh,
      lastDetailRefresh: detailStale ? now : p.lastDetailRefresh,
      productTags: detailStale ? live.productTags : p.productTags,
      productSashes: detailStale ? live.productSashes : p.productSashes,
      availablePackTypes: priceStale ? live.availablePackTypes : p.availablePackTypes,
    );

    _cacheProduct(updated);
    return updated;
  }
}

class _ScoredProduct {
  final Product product;
  final double score;
  _ScoredProduct(this.product, this.score);
}
