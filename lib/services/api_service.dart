import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import '../models/product.dart';
import 'cache_service.dart';
import 'search_service.dart';

class ApiService {
  // All DM API calls go through our server — the key never leaves the backend.
  static const _serverBase = 'http://192.168.1.108:8000';
  static const _prodBase = 'https://mydans.calvfletch.dev';

  static bool _useProd = false;
  static String get _base => _useProd ? _prodBase : _serverBase;

  // In-memory catalog
  static final List<Product> _catalog = [];
  static bool _loaded = false;

  static bool get isLoaded => _loaded;
  static int get catalogSize => _catalog.length;

  /// Load catalog: cache first, then refresh from API in background.
  static Future<void> initCatalog() async {
    // 1. Load from cache immediately
    final cached = await CacheService.loadCatalog();
    print('[CATALOG] Cache loaded: ${cached.length} products');
    if (cached.isNotEmpty) {
      _catalog.clear();
      _catalog.addAll(cached);
      _loaded = true;
    }

    // 2. Refresh from API in background
    _refreshCatalog();
  }

  static Future<void> _refreshCatalog() async {
    final fresh = <Product>[];
    try {
      for (var page = 1; page <= 77; page++) {
        final response = await http.post(
          Uri.parse('$_base/api/catalog/offers'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'PageNumber': page, 'PageSize': 50}),
        );
        if (response.statusCode != 200) {
          print('[CATALOG] API page $page returned ${response.statusCode}');
          break;
        }
        final data = json.decode(response.body);
        final products = data['products'] as List<dynamic>? ?? [];
        if (products.isEmpty) break;
        for (final p in products) {
          fresh.add(_buildOffer(p as Map<String, dynamic>));
        }
      }
      print(
        '[CATALOG] API fetched ${fresh.length} products from ${(fresh.length / 50).ceil()} pages',
      );
    } catch (e) {
      print('[CATALOG] API error: $e');
    }

    if (fresh.isNotEmpty) {
      _catalog.clear();
      _catalog.addAll(fresh);
      _loaded = true;
      CacheService.saveCatalog(fresh);
      print('[CATALOG] Total loaded: ${_catalog.length}');
    } else {
      print('[CATALOG] No fresh products, keeping ${_catalog.length} cached');
    }
  }

  static Product _buildOffer(Map<String, dynamic> json) {
    final prices = <ProductPrice>[];
    final priceList = json['price'] as List<dynamic>? ?? [];
    for (final p in priceList) {
      final pm = p as Map<String, dynamic>;
      prices.add(
        ProductPrice(
          type: (pm['priceType'] ?? '').toString(),
          message: (pm['message'] ?? '').toString(),
          value: (pm['value'] ?? 0).toDouble(),
          preText: (pm['offerPreText'] ?? '').toString(),
          isMemberOffer: pm['isMemberOffer'] == true,
          packType: (pm['packType'] ?? '').toString(),
          beforePromotion: (pm['beforePromotion'] ?? 0).toDouble(),
          afterPromotion: (pm['afterPromotion'] ?? 0).toDouble(),
        ),
      );
    }

    return Product.fromOfferJson({
      'stockcode': (json['id'] ?? '').toString(),
      'title': (json['title'] ?? '').toString(),
      'brand': (json['brand'] ?? '').toString(),
      'description': '',
      'richDescription': '',
      'packageSize': '',
      'alcoholVolume': '',
      'varietal': '',
      'region': '',
      'state': '',
      'country': '',
      'vintage': '',
      'closure': '',
      'standardDrinks': '',
      'wineBody': '',
      'wineSweetness': '',
      'averageRating': (json['ratingCount'] ?? 0).toDouble(),
      'totalReviewCount': json['totalReviewCount'] ?? 0,
      'smallImageUrl': '',
      'mediumImageUrl': '',
      'largeImageUrl': '',
      'imageVariants': [],
      'prices': prices
          .map(
            (p) => {
              'type': p.type,
              'message': p.message,
              'value': p.value,
              'preText': p.preText,
              'isMemberOffer': p.isMemberOffer,
              'packType': p.packType,
              'beforePromotion': p.beforePromotion,
              'afterPromotion': p.afterPromotion,
            },
          )
          .toList(),
      'stockOnHand': 0,
      'isOnSpecial': prices.any((p) => p.isMemberOffer),
      'categories': [],
    });
  }

  /// Fetch full product detail by stock code
  /// Optionally pass storeNo for store-specific stock.
  static Future<Product?> getProduct(
    String stockcode, {
    String? storeNo,
  }) async {
    try {
      final uri = storeNo != null && storeNo.isNotEmpty
          ? '$_base/product/$stockcode?store=$storeNo'
          : '$_base/product/$stockcode';
      final response = await http.get(Uri.parse(uri));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final products = data['Products'] as List<dynamic>?;
        if (products != null && products.isNotEmpty) {
          return Product.fromJson(products[0] as Map<String, dynamic>);
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get delivery availability for a product at a store
  static Future<Map<String, dynamic>?> getDeliveryOptions(
    String stockcode,
    String storeNo,
  ) async {
    try {
      final response = await http.get(
        Uri.parse('$_base/product/$stockcode/delivery?store=$storeNo'),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Instant in-memory search + API fallback for codes in mixed queries
  static List<Product> searchSync(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty || !_loaded) return [];

    // Pure code: catalog first, then API fallback
    if (RegExp(r'^\d+$').hasMatch(trimmed)) {
      final cached = _catalog.where((p) => p.stockcode == trimmed).toList();
      return cached;
    }

    // Split by whitespace AND digit/non-digit boundaries (e.g. "398penfold" → ["398","penfold"])
    final lower = trimmed.toLowerCase();
    final rawParts = lower
        .replaceAll(RegExp(r'(\d)([a-z])'), r'$1 $2')
        .replaceAll(RegExp(r'([a-z])(\d)'), r'$1 $2')
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();

    final codes = rawParts.where((w) => RegExp(r'^\d+$').hasMatch(w)).toList();
    final textWords = rawParts
        .where((w) => !RegExp(r'^\d+$').hasMatch(w))
        .toList();

    // Text search in catalog
    List<Product> results = [];
    if (textWords.isNotEmpty) {
      results = _catalog.where((p) {
        final text =
            '${p.title.toLowerCase()} ${p.brand.toLowerCase()} ${p.stockcode}';
        return textWords.every((qw) => text.contains(qw));
      }).toList();
    }

    // Also match by stock code for numeric words
    for (final code in codes) {
      final codeMatches = _catalog
          .where((p) => p.stockcode.contains(code) || p.stockcode == code)
          .toList();
      for (final m in codeMatches) {
        if (!results.any((r) => r.stockcode == m.stockcode)) {
          results.add(m);
        }
      }
    }

    return _consolidateMultipacks(results);
  }

  /// Delegate to SearchService (local fuzzy + web fallback with caching)
  static Future<List<Product>> searchWithApi(
    String query, {
    void Function()? onUpdated,
  }) => SearchService.search(query, onUpdated: onUpdated);

  /// Web search API fallback for text queries
  static Future<List<Product>> webSearch(String query) async {
    try {
      http.Response response;
      if (proxyBase != null) {
        // Route through PC proxy (VPN interface)
        final proxyUrl = Uri.parse(
          '$proxyBase/search',
        ).replace(queryParameters: {'q': query});
        response = await http
            .get(proxyUrl)
            .timeout(const Duration(seconds: 15));
        print('[PROXY] Search "$query" → ${response.statusCode}');
      } else {
        response = await http
            .post(
              Uri.parse('$_base/search'),
              headers: {'Content-Type': 'application/json'},
              body: json.encode({
                'Filters': '',
                'SearchTerm': query,
                'PageSize': '20',
                'PageNumber': '1',
                'SortType': 'Relevance',
                'Location': '',
                'PageUrl': '/search?searchTerm=${Uri.encodeComponent(query)}',
              }),
            )
            .timeout(const Duration(seconds: 8));
      }
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final products = data['Products'] as List<dynamic>? ?? [];
        return products
            .map((p) => Product.fromSearchJson(p as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      print('[WEBSEARCH] Error: $e');
    }
    return [];
  }

  /// Group multipack variants (e.g. 6-pack vs single of same product)
  static List<Product> _consolidateMultipacks(List<Product> products) {
    final Map<String, List<Product>> groups = {};

    for (final p in products) {
      final key =
          '${p.brand.toLowerCase()}|${_stripVolume(p.title.toLowerCase())}';
      groups.putIfAbsent(key, () => []).add(p);
    }

    final result = <Product>[];
    for (final entry in groups.entries) {
      entry.value.sort((a, b) => a.title.length.compareTo(b.title.length));
      result.add(entry.value.first);
    }
    return result;
  }

  static String _stripVolume(String title) {
    return title
        .replaceAll(RegExp(r'\d+\s*x\s*\d+\s*ml'), '')
        .replaceAll(RegExp(r'\d+\s*ml'), '')
        .replaceAll(RegExp(r'\d+\.?\d*\s*l(?![a-z])'), '')
        .replaceAll(
          RegExp(r'\b(cans?|bottles?|cartons?|cases?|packs?|slabs?|casks?)\b'),
          '',
        )
        .replaceAll(RegExp(r'\d+\s*pk\b'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Search stores by postcode or suburb
  static Future<List<Map<String, dynamic>>> searchStores(String query) async {
    try {
      final uri = Uri.parse('$_base/stores/search?postcode=$query');
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final stores = data['Stores'] as List<dynamic>? ?? [];
        return stores.map((s) => s as Map<String, dynamic>).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Get nearby store stock for a product
  static Future<List<Map<String, dynamic>>> getNearbyStock(
    String stockcode,
    String postcode,
  ) async {
    try {
      final uri = Uri.parse(
        '$_base/stores/nearby?postcode=$postcode&stockcode=$stockcode',
      );
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return (data['StoreStockDetails'] as List<dynamic>?)
                ?.map((s) => s as Map<String, dynamic>)
                .toList() ??
            [];
      }
    } catch (_) {}
    return [];
  }

  /// Get cardinal direction from origin to target (lat/lng in degrees)
  static String cardinalDirection(
    double fromLat,
    double fromLng,
    double toLat,
    double toLng,
  ) {
    final dLat = (toLat - fromLat) * math.pi / 180;
    final dLng = (toLng - fromLng) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(toLat * math.pi / 180);
    final x =
        math.cos(fromLat * math.pi / 180) * math.sin(toLat * math.pi / 180) -
        math.sin(fromLat * math.pi / 180) *
            math.cos(toLat * math.pi / 180) *
            math.cos(dLng);
    final deg = (math.atan2(y, x) * 180 / math.pi + 360) % 360;
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final ix = ((deg + 22.5) / 45).round() % 8;
    return dirs[ix];
  }

  /// Get customer reviews
  static Future<Map<String, dynamic>?> getReviews(
    String productCode, {
    int page = 1,
    int pageSize = 10,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_base/reviews'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'productCode': productCode,
          'page': page,
          'pageSize': pageSize,
        }),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Auth
  // ═══════════════════════════════════════════════════════════════

  /// Register and get a basic API token. Everyone gets one automatically.
  static Future<String?> register() async {
    try {
      final r = await http.post(Uri.parse('$_base/api/auth/register'));
      if (r.statusCode == 201) {
        final data = json.decode(r.body);
        final token = data['token'] as String;
        await CacheService.setToken(token);
        await CacheService.setTokenTier(data['tier'] ?? 'basic');
        return token;
      }
    } catch (_) {}
    return null;
  }

  /// Request advanced access upgrade. Requires store details.
  static Future<Map<String, dynamic>?> requestUpgrade({
    required String storeNumber,
    required String name,
    required String employeeId,
    required String passphrase,
  }) async {
    try {
      final r = await http.post(
        Uri.parse('$_base/api/auth/request'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'store_number': storeNumber,
          'name': name,
          'employee_id': employeeId,
          'passphrase': passphrase,
        }),
      );
      if (r.statusCode == 201) {
        return json.decode(r.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Poll request status until approved/rejected.
  static Future<String?> checkRequestStatus(String requestId) async {
    try {
      final r = await http.get(Uri.parse('$_base/api/auth/status/$requestId'));
      if (r.statusCode == 200) {
        final data = json.decode(r.body);
        if (data['status'] == 'approved' && data['token'] != null) {
          await CacheService.setToken(data['token'] as String);
          await CacheService.setTokenTier('advanced');
          return 'approved';
        }
        return data['status'] as String?;
      }
    } catch (_) {}
    return null;
  }

  // ═══════════════════════════════════════════════════════════════
  // Search Compare (local-first workflow)
  // ═══════════════════════════════════════════════════════════════

  /// Client sends local search results → server returns ordering + missing + refreshed.
  static Future<Map<String, dynamic>?> searchCompare({
    required String query,
    required int localCount,
    required List<String> staleIds,
  }) async {
    try {
      final r = await http.post(
        Uri.parse('$_base/api/search/compare'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'query': query,
          'local_count': localCount,
          'stale_ids': staleIds,
        }),
      );
      if (r.statusCode == 200) {
        return json.decode(r.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Get product detail (for fetching missing/refreshed products).
  static Future<Product?> getProduct(String code) async {
    try {
      final r = await http.get(Uri.parse('$_base/api/product/$code'));
      if (r.statusCode == 200) {
        return Product.fromJson(json.decode(r.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  /// Get current auth token from cache.
  static Future<String?> getToken() => CacheService.getToken();

  /// Get current tier.
  static Future<String> getTier() async {
    final t = await CacheService.getTokenTier();
    return t ?? 'basic';
  }
}
