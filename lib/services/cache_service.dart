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

  static Future<bool> getDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_darkModeKey) ?? false;
  }

  static Future<void> setDarkMode(bool dark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModeKey, dark);
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
