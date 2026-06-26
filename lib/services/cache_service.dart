import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';

class CacheService {
  static const _catalogKey = 'cached_catalog';
  static const _timestampKey = 'catalog_timestamp';
  static const _storeNoKey = 'store_no';
  static const _storeNameKey = 'store_name';
  static const _postcodeKey = 'postcode';
  static const _darkModeKey = 'dark_mode';
  static const _teamDiscountKey = 'team_discount';
  static const _syncTimeKey = 'sync_time';
  static const _lastSyncKey = 'last_sync_time';
  static const _apiBaseKey = 'api_base_url';
  static const _cacheMaxAge = Duration(hours: 2);

  // --- Product Catalog Cache ---

  static Future<List<Product>> loadCatalog() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_catalogKey);
    if (jsonStr == null) return [];

    try {
      final list = json.decode(jsonStr) as List<dynamic>;
      return list
          .map((e) => Product.fromOfferJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveCatalog(List<Product> products) async {
    final prefs = await SharedPreferences.getInstance();
    final list = products.map((p) => p.toOfferJson()).toList();
    await prefs.setString(_catalogKey, json.encode(list));
    await prefs.setInt(_timestampKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<DateTime?> getCatalogAge() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt(_timestampKey);
    if (ts == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ts);
  }

  static Future<bool> isCacheStale() async {
    final age = await getCatalogAge();
    if (age == null) return true;
    return DateTime.now().difference(age) > _cacheMaxAge;
  }

  // --- Store Settings ---

  static Future<String> getStoreNo() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_storeNoKey) ?? '';
  }

  static Future<void> setStoreNo(String storeNo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storeNoKey, storeNo);
  }

  static Future<String> getStoreName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_storeNameKey) ?? '';
  }

  static Future<void> setStoreName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storeNameKey, name);
  }

  static Future<String> getPostcode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_postcodeKey) ?? '2000';
  }

  static Future<void> setPostcode(String postcode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_postcodeKey, postcode);
  }

  // --- Theme ---

  static Future<String> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_darkModeKey) ?? 'system';
  }

  static Future<void> setThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_darkModeKey, mode);
  }

  // --- Team Discount ---

  /// Whether to show team discount prices (if eligible)
  static Future<bool> getTeamDiscount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_teamDiscountKey) ?? false;
  }

  static Future<void> setTeamDiscount(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_teamDiscountKey, show);
  }

  // --- Nightly Sync ---

  /// Get preferred sync hour (0-23). Default 1 (1am). -1 = manual only.
  static Future<int> getSyncHour() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_syncTimeKey) ?? 2;
  }

  static Future<void> setSyncHour(int hour) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_syncTimeKey, hour);
  }

  /// Last time a nightly sync completed
  static Future<DateTime?> getLastSync() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt(_lastSyncKey);
    if (ts == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ts);
  }

  static Future<void> setLastSync(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastSyncKey, time.millisecondsSinceEpoch);
  }

  /// API base URL for our backend
  static Future<String> getApiBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiBaseKey) ?? 'https://mydans.calvfletch.dev';
  }

  static Future<void> setApiBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiBaseKey, url);
  }

  /// Check if a product has a team/member price from the API.
  /// The API returns `promoprice` with `IsMemberOffer: true` for team-eligible products.
  /// No calculation needed — the API gives the actual team price.
  static bool hasTeamPrice(List<dynamic>? prices) {
    if (prices == null) return false;
    for (final p in prices) {
      if (p is Map && p['isMemberOffer'] == true) return true;
    }
    return false;
  }

  /// Get the team/member price from API data.
  /// Returns the promo price value, or null if not team-eligible.
  static double? teamPrice(List<dynamic>? prices) {
    if (prices == null) return null;
    for (final p in prices) {
      if (p is Map && p['isMemberOffer'] == true) {
        final v = p['value'];
        if (v is num && v > 0) return v.toDouble();
      }
    }
    return null;
  }

  // --- Local Product Database ---

  static const _productDbKey = 'product_db';

  /// Load all cached products
  static Future<Map<String, Product>> loadProductDb() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_productDbKey);
    if (jsonStr == null) return {};

    try {
      final map = json.decode(jsonStr) as Map<String, dynamic>;
      return map.map(
        (k, v) => MapEntry(k, Product.fromOfferJson(v as Map<String, dynamic>)),
      );
    } catch (_) {
      return {};
    }
  }

  /// Save product database
  static Future<void> saveProductDb(Map<String, Product> db) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonMap = db.map((k, v) => MapEntry(k, v.toOfferJson()));
    await prefs.setString(_productDbKey, json.encode(jsonMap));
  }

  /// Check cache age for background refresh
  static Future<DateTime?> getProductDbAge() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt('product_db_timestamp');
    if (ts == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ts);
  }

  static Future<void> _touchProductDb() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'product_db_timestamp',
      DateTime.now().millisecondsSinceEpoch,
    );
  }
}
