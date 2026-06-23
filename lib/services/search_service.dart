import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/product.dart';
import 'cache_service.dart';
import 'api_service.dart';

/// Own fuzzy search engine over locally cached products.
/// Learns over time — every search caches new products.
class SearchService {
  static final Map<String, Product> _db = {};

  static Map<String, Product> get database => _db;
  static int get size => _db.length;

  /// Load cached products on startup, bundled DB first
  static Future<void> init() async {
    // 1. Load bundled init database (ships with app)
    try {
      final jsonStr = await rootBundle.loadString('assets/init_db.json');
      final map = json.decode(jsonStr) as Map<String, dynamic>;
      for (final entry in map.entries) {
        _db[entry.key] = Product.fromOfferJson(
          entry.value as Map<String, dynamic>,
        );
      }
      print('[DB] Loaded ${_db.length} products from bundled init DB');
    } catch (_) {
      print('[DB] No bundled init DB found, starting fresh');
    }

    // 2. Load any additional cached products from SharedPreferences
    final cached = await CacheService.loadProductDb();
    for (final entry in cached.entries) {
      _db.putIfAbsent(entry.key, () => entry.value);
    }
    print('[DB] Total local products: ${_db.length}');
  }

  /// Main search: fuzzy local + always fetch web to grow DB
  static Future<List<Product>> search(String query) async {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return [];

    // 1. Fuzzy match against local DB (instant)
    final localResults = _fuzzyMatch(trimmed);

    // 2. Always fetch from web API to grow DB (fire-and-forget-ish, but await first batch)
    if (trimmed.length >= 2) {
      final webResults = await ApiService.webSearch(query);
      for (final p in webResults) {
        _cacheProduct(p);
      }
    }

    // 3. Re-search local after caching (now has more products)
    if (localResults.length < 3) {
      return _fuzzyMatch(trimmed);
    }

    return localResults;
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

  /// Cache a product locally — upsert with history tracking
  static void _cacheProduct(Product incoming) {
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
        smallImageUrl: incoming.smallImageUrl.isNotEmpty
            ? incoming.smallImageUrl
            : existing.smallImageUrl,
        mediumImageUrl: incoming.mediumImageUrl.isNotEmpty
            ? incoming.mediumImageUrl
            : existing.mediumImageUrl,
        largeImageUrl: incoming.largeImageUrl.isNotEmpty
            ? incoming.largeImageUrl
            : existing.largeImageUrl,
        imageVariants: incoming.imageVariants.isNotEmpty
            ? incoming.imageVariants
            : existing.imageVariants,
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

  /// Hydrate live price/stock for a product (call when displaying)
  static Future<Product> hydrate(Product p, {String? storeNo}) async {
    final live = await ApiService.getProduct(p.stockcode, storeNo: storeNo);
    if (live != null) {
      _cacheProduct(live); // upsert with history tracking
      return _db[p.stockcode]!;
    }
    return p;
  }
}

class _ScoredProduct {
  final Product product;
  final double score;
  _ScoredProduct(this.product, this.score);
}
