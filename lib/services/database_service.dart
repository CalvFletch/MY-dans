import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import '../models/product.dart';
import '../models/product.dart';

/// SQLite-backed product database.
/// Replaces the in-memory Map<String, Product> with indexed, searchable storage.
///
/// On first launch, copies the bundled `assets/init_db.json` into SQLite.
/// Future launches load directly from SQLite.
class DatabaseService {
  static DatabaseService? _instance;
  static DatabaseService get instance => _instance!;

  Database? _db;
  bool _ready = false;

  Database get db => _db!;
  bool get isReady => _ready;
  int _count = 0;
  int get count => _count;

  static Future<void> init() async {
    _instance = DatabaseService();
    await _instance!._open();
  }

  Future<void> _open() async {
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, 'mydans.db'),
      version: 3,
      onCreate: _createTables,
      onUpgrade: _migrate,
    );
    _count =
        Sqflite.firstIntValue(
          await _db!.rawQuery('SELECT COUNT(*) FROM products'),
        ) ??
        0;
    _ready = true;
    print('[SQLite] Opened DB with $_count products');

    // If empty, seed from bundled JSON
    if (_count == 0) {
      await _seedFromBundle();
    }
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products (
        stockcode         TEXT PRIMARY KEY NOT NULL,
        title             TEXT NOT NULL,
        brand             TEXT NOT NULL DEFAULT '',
        description       TEXT NOT NULL DEFAULT '',
        rich_description  TEXT NOT NULL DEFAULT '',
        package_size      TEXT NOT NULL DEFAULT '',
        alcohol_volume    TEXT NOT NULL DEFAULT '',
        varietal          TEXT NOT NULL DEFAULT '',
        region            TEXT NOT NULL DEFAULT '',
        state             TEXT NOT NULL DEFAULT '',
        country           TEXT NOT NULL DEFAULT '',
        vintage           TEXT NOT NULL DEFAULT '',
        closure           TEXT NOT NULL DEFAULT '',
        standard_drinks   TEXT NOT NULL DEFAULT '',
        wine_body         TEXT NOT NULL DEFAULT '',
        wine_sweetness    TEXT NOT NULL DEFAULT '',
        avg_rating        REAL NOT NULL DEFAULT 0,
        review_count      INTEGER NOT NULL DEFAULT 0,
        categories        TEXT NOT NULL DEFAULT '[]',
        product_tags      TEXT NOT NULL DEFAULT '[]',
        product_sashes    TEXT NOT NULL DEFAULT '[]',
        prices            TEXT NOT NULL DEFAULT '[]',
        stock_on_hand     INTEGER NOT NULL DEFAULT 0,
        backorder_stock   INTEGER NOT NULL DEFAULT 0,
        backorder_message TEXT NOT NULL DEFAULT '',
        is_purchasable    INTEGER NOT NULL DEFAULT 1,
        is_on_special     INTEGER NOT NULL DEFAULT 0,
        is_member_special INTEGER NOT NULL DEFAULT 0,
        is_delivery_only  INTEGER NOT NULL DEFAULT 0,
        is_edr_special    INTEGER NOT NULL DEFAULT 0,
        is_find_me_avail  INTEGER NOT NULL DEFAULT 0,
        age_restricted    INTEGER NOT NULL DEFAULT 0,
        unit              TEXT NOT NULL DEFAULT '',
        pkg_size_display  TEXT NOT NULL DEFAULT '',
        parent_stockcode  TEXT NOT NULL DEFAULT '',
        source            TEXT NOT NULL DEFAULT '',
        available_pack_types TEXT NOT NULL DEFAULT '[]',
        first_seen        TEXT
      )
    ''');

    await db.execute('CREATE INDEX idx_p_brand ON products(brand)');
    await db.execute('CREATE INDEX idx_p_country ON products(country)');
    await db.execute('CREATE INDEX idx_p_review_count ON products(review_count)');

    await db.execute('''
      CREATE VIRTUAL TABLE products_fts USING fts4(
        stockcode, title, brand, description
      )
    ''');

    await db.execute('''
      CREATE TABLE price_history (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        stockcode   TEXT NOT NULL REFERENCES products(stockcode),
        price_type  TEXT NOT NULL DEFAULT 'singleprice',
        value       REAL NOT NULL,
        recorded_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    await db.execute('CREATE INDEX idx_ph_stockcode ON price_history(stockcode)');

    await db.execute('''
      CREATE TABLE previous_titles (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        stockcode   TEXT NOT NULL REFERENCES products(stockcode),
        title       TEXT NOT NULL,
        changed_at  TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    print('[SQLite] Tables created (v2)');
  }

  Future<void> _migrate(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute("ALTER TABLE products ADD COLUMN backorder_stock INTEGER NOT NULL DEFAULT 0");
      await db.execute("ALTER TABLE products ADD COLUMN backorder_message TEXT NOT NULL DEFAULT ''");
      await db.execute("ALTER TABLE products ADD COLUMN is_delivery_only INTEGER NOT NULL DEFAULT 0");
      await db.execute("ALTER TABLE products ADD COLUMN is_edr_special INTEGER NOT NULL DEFAULT 0");
      await db.execute("ALTER TABLE products ADD COLUMN is_find_me_avail INTEGER NOT NULL DEFAULT 0");
      await db.execute("ALTER TABLE products ADD COLUMN age_restricted INTEGER NOT NULL DEFAULT 0");
      await db.execute("ALTER TABLE products ADD COLUMN unit TEXT NOT NULL DEFAULT ''");
      await db.execute("ALTER TABLE products ADD COLUMN pkg_size_display TEXT NOT NULL DEFAULT ''");
      await db.execute("ALTER TABLE products ADD COLUMN parent_stockcode TEXT NOT NULL DEFAULT ''");
      await db.execute("ALTER TABLE products ADD COLUMN source TEXT NOT NULL DEFAULT ''");
      await db.execute("ALTER TABLE products ADD COLUMN available_pack_types TEXT NOT NULL DEFAULT '[]'");
    }
  }

  /// Seed from bundled JSON (first launch)
  Future<void> _seedFromBundle() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/init_db.json');
      final decoded = json.decode(jsonStr);
      final batch = _db!.batch();

      if (decoded is List) {
        // Array format [{stockcode:..., ...}, ...]
        for (final p in decoded) {
          if (p is Map<String, dynamic>) {
            final sc = (p['stockcode'] ?? '').toString();
            if (sc.isNotEmpty) _insertProduct(batch, sc, p);
          }
        }
        _count = decoded.length;
      } else if (decoded is Map) {
        // Map format {stockcode: {...}, ...}
        for (final entry in (decoded as Map<String, dynamic>).entries) {
          final p = entry.value as Map<String, dynamic>;
          _insertProduct(batch, entry.key, p);
        }
        _count = decoded.length;
      }

      await batch.commit(noResult: true);
      _rebuildFts();
      print('[SQLite] Seeded $_count products from bundled JSON');
    } catch (e) {
      print('[SQLite] No bundled DB found, starting empty: $e');
    }
  }

  /// Insert or update a product
  Future<void> upsertProduct(
    String stockcode,
    Map<String, dynamic> data,
  ) async {
    final batch = _db!.batch();
    _insertProduct(batch, stockcode, data);
    await batch.commit(noResult: true);
    _count =
        Sqflite.firstIntValue(
          await _db!.rawQuery('SELECT COUNT(*) FROM products'),
        ) ??
        _count;
  }

  /// Batch-insert many products (from scraper output)
  Future<void> bulkInsert(Map<String, Map<String, dynamic>> products) async {
    final batch = _db!.batch();
    for (final entry in products.entries) {
      _insertProduct(batch, entry.key, entry.value);
    }
    await batch.commit(noResult: true);
    _count =
        Sqflite.firstIntValue(
          await _db!.rawQuery('SELECT COUNT(*) FROM products'),
        ) ??
        _count;
    _rebuildFts();
    print(
      '[SQLite] Bulk inserted ${products.length} products (total: $_count)',
    );
  }

  void _insertProduct(
    Batch batch,
    String stockcode,
    Map<String, dynamic> json,
  ) {
    batch.insert('products', {
      'stockcode': stockcode,
      'title': (json['title'] ?? '').toString(),
      'brand': (json['brand'] ?? '').toString(),
      'description': (json['description'] ?? '').toString(),
      'rich_description': (json['richDescription'] ?? '').toString(),
      'package_size': (json['packageSize'] ?? '').toString(),
      'alcohol_volume': (json['alcoholVolume'] ?? '').toString(),
      'varietal': (json['varietal'] ?? '').toString(),
      'region': (json['region'] ?? '').toString(),
      'state': (json['state'] ?? '').toString(),
      'country': (json['country'] ?? '').toString(),
      'vintage': (json['vintage'] ?? '').toString(),
      'closure': (json['closure'] ?? '').toString(),
      'standard_drinks': (json['standardDrinks'] ?? '').toString(),
      'wine_body': (json['wineBody'] ?? '').toString(),
      'wine_sweetness': (json['wineSweetness'] ?? '').toString(),
      'avg_rating': json['averageRating'] ?? 0,
      'review_count': json['totalReviewCount'] ?? 0,
      'categories': jsonEncode(json['categories'] ?? []),
      'product_tags': jsonEncode(json['productTags'] ?? []),
      'product_sashes': jsonEncode(json['productSashes'] ?? []),
      'prices': jsonEncode(json['prices'] ?? []),
      'stock_on_hand': json['stockOnHand'] ?? 0,
      'is_purchasable': json['isPurchasable'] == true ? 1 : 0,
      'is_on_special': json['isOnSpecial'] == true ? 1 : 0,
      'is_member_special': json['isMemberSpecial'] == true ? 1 : 0,
      'is_delivery_only': json['isDeliveryOnly'] == true ? 1 : 0,
      'is_edr_special': json['isEdrSpecial'] == true ? 1 : 0,
      'is_find_me_avail': json['isFindMeAvailable'] == true ? 1 : 0,
      'age_restricted': json['ageRestricted'] == true ? 1 : 0,
      'backorder_message': (json['backorderMessage'] ?? '').toString(),
      'backorder_stock': json['backorderStockOnHand'] ?? 0,
      'available_pack_types': jsonEncode(json['availablePackTypes'] ?? []),
      'unit': (json['unit'] ?? '').toString(),
      'pkg_size_display': (json['packageSizeDisplay'] ?? '').toString(),
      'parent_stockcode': (json['parentStockCode'] ?? '').toString(),
      'source': (json['source'] ?? '').toString(),
      'first_seen': json['firstSeen']?.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Full-text search using FTS4
  Future<List<Product>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    // FTS4 query with prefix matching
    final ftsQuery = trimmed
        .split(RegExp(r'\s+'))
        .map((w) => '"$w"*')
        .join(' OR ');

    final rows = await _db!.rawQuery(
      '''
      SELECT p.* FROM products p
      JOIN products_fts fts ON p.rowid = fts.docid
      WHERE products_fts MATCH ?
      LIMIT 100
    ''',
      [ftsQuery],
    );

    final results = <Product>[];
    for (final r in rows) {
      try {
        results.add(_rowToProduct(r));
      } catch (_) {}
    }

    // If FTS didn't find enough, fall back to LIKE search
    if (results.length < 5) {
      try {
        final likeResults = await _likeSearch(trimmed);
        final existingCodes = results.map((p) => p.stockcode).toSet();
        for (final p in likeResults) {
          if (!existingCodes.contains(p.stockcode)) {
            results.add(p);
          }
        }
      } catch (_) {}
    }

    return results.take(30).toList();
  }

  /// Fallback LIKE search for partial matches
  Future<List<Product>> _likeSearch(String query) async {
    final like = '%$query%';
    final rows = await _db!.rawQuery(
      '''
      SELECT * FROM products
      WHERE stockcode = ? OR stockcode LIKE ? OR title LIKE ? OR brand LIKE ?
      LIMIT 50
    ''',
      [query, '$query%', like, like],
    );
    return rows.map((r) => _rowToProduct(r)).toList();
  }

  /// Get a single product by stockcode
  Future<Product?> getProduct(String stockcode) async {
    final rows = await _db!.query(
      'products',
      where: 'stockcode = ?',
      whereArgs: [stockcode],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToProduct(rows.first);
  }

  /// Get products matching category filter
  Future<List<Product>> getByCategory(String category) async {
    final rows = await _db!.rawQuery(
      "SELECT * FROM products WHERE categories LIKE ? LIMIT 200",
      ['%$category%'],
    );
    return rows.map((r) => _rowToProduct(r)).toList();
  }

  /// Get new products (first seen within N days)
  Future<List<Product>> getNewProducts(int days) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final rows = await _db!.query(
      'products',
      where: 'first_seen >= ?',
      whereArgs: [cutoff.toIso8601String()],
      limit: 200,
    );
    return rows.map((r) => _rowToProduct(r)).toList();
  }

  /// Rebuild FTS index from products table
  Future<void> _rebuildFts() async {
    await _db!.execute('DELETE FROM products_fts');
    await _db!.execute('''
      INSERT INTO products_fts(docid, stockcode, title, brand, description)
      SELECT rowid, stockcode, title, brand, description FROM products
    ''');
  }

  /// Parse a JSON string column into a List<String>
  List<String> _parseStringList(String? raw) {
    if (raw == null || raw.isEmpty || raw == '[]') return [];
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  /// Parse a JSON string column into a Map<String, dynamic>
  Map<String, dynamic> _parseJsonMap(String? raw) {
    if (raw == null || raw.isEmpty || raw == '{}') return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  /// Parse a JSON string column into a List<Map<String, dynamic>>
  List<Map<String, dynamic>> _parseJsonList(String? raw) {
    if (raw == null || raw.isEmpty || raw == '[]') return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map(
            (e) =>
                e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{},
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Parse prices JSON into ProductPrice list
  List<ProductPrice> _parsePrices(String? raw) {
    if (raw == null || raw.isEmpty || raw == '[]') return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) {
        final m = e as Map<String, dynamic>;
        return ProductPrice(
          type: (m['type'] ?? '').toString(),
          message: (m['message'] ?? '').toString(),
          value: (m['value'] ?? 0).toDouble(),
          preText: (m['preText'] ?? '').toString(),
          isMemberOffer: m['isMemberOffer'] == true,
          packType: (m['packType'] ?? '').toString(),
          beforePromotion: (m['beforePromotion'] ?? 0).toDouble(),
          afterPromotion: (m['afterPromotion'] ?? 0).toDouble(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Convert a database row to a Product object
  Product _rowToProduct(Map<String, dynamic> row) {
    final categories = _parseStringList(row['categories'] as String?);
    return Product(
      stockcode: row['stockcode'] as String,
      title: row['title'] as String? ?? '',
      brand: row['brand'] as String? ?? '',
      description: row['description'] as String? ?? '',
      richDescription: row['rich_description'] as String? ?? '',
      packageSize: row['package_size'] as String? ?? '',
      alcoholVolume: (row['alcohol_volume'] ?? '').toString(),
      varietal: row['varietal'] as String? ?? '',
      region: row['region'] as String? ?? '',
      state: row['state'] as String? ?? '',
      country: row['country'] as String? ?? '',
      vintage: (row['vintage'] ?? '').toString(),
      closure: row['closure'] as String? ?? '',
      standardDrinks: (row['standard_drinks'] ?? '').toString(),
      wineBody: row['wine_body'] as String? ?? '',
      wineSweetness: row['wine_sweetness'] as String? ?? '',
      averageRating: (row['avg_rating'] as num?)?.toDouble(),
      totalReviewCount: row['review_count'] as int? ?? 0,
      prices: _parsePrices(row['prices'] as String?),
      stockOnHand: row['stock_on_hand'] as int? ?? 0,
      isPurchasable: row['is_purchasable'] == 1,
      isOnSpecial: row['is_on_special'] == 1,
      isMemberSpecial: row['is_member_special'] == 1,
      categories: categories,
      productTags: _parseJsonList(row['product_tags'] as String?),
      productSashes: _parseJsonList(row['product_sashes'] as String?),
      availablePackTypes: _parseJsonList(row['available_pack_types'] as String?),
      backorderMessage: row['backorder_message'] as String? ?? '',
      isDeliveryOnly: row['is_delivery_only'] == 1,
      isEdrSpecial: row['is_edr_special'] == 1,
      isFindMeAvailable: row['is_find_me_avail'] == 1,
      ageRestricted: row['age_restricted'] == 1,
      unit: row['unit'] as String? ?? '',
      packageSizeDisplay: row['pkg_size_display'] as String? ?? '',
      parentStockCode: row['parent_stockcode'] as String? ?? '',
      source: row['source'] as String? ?? '',
      firstSeen: row['first_seen'] != null ? DateTime.tryParse(row['first_seen'] as String) : null,
    );
  }

  /// Close the database
  Future<void> close() async {
    await _db?.close();
    _ready = false;
  }
}
