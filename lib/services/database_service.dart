import 'dart:convert';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'package:dart_lz4/dart_lz4.dart';
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
    final dbDir = await getDatabasesPath();
    final dbFile = p.join(dbDir, 'mydans.db');

    // Copy pre-built DB from assets if not exists
    if (!File(dbFile).existsSync()) {
      try {
        final data = await rootBundle.load('assets/mydans.db.lz4');
        final bytes = data.buffer.asUint8List();
        final origSize =
            (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
        final decompressed = lz4Decompress(
          bytes.sublist(4),
          decompressedSize: origSize,
        );
        await File(dbFile).writeAsBytes(decompressed);
        print('[SQLite] Copied pre-built DB from assets (LZ4)');
      } catch (e) {
        print('[SQLite] No pre-built DB: $e');
      }
    }

    _db = await openDatabase(
      dbFile,
      version: 5,
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

    // Build FTS index if missing (desktop SQLite skips FTS4)
    try {
      await _db!.execute(
        'CREATE VIRTUAL TABLE IF NOT EXISTS products_fts USING fts4(stockcode, title, brand, description)',
      );
      await _db!.rawQuery('SELECT COUNT(*) FROM products_fts').then((r) {
        if (Sqflite.firstIntValue(r) == 0) _rebuildFts();
      });
    } catch (_) {}

    // If still empty, try legacy JSON seed
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
        product_type      TEXT NOT NULL DEFAULT '',
        main_category     TEXT NOT NULL DEFAULT '',
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
        first_seen        TEXT,
        min_price         REAL NOT NULL DEFAULT 0,
        url_friendly_name TEXT NOT NULL DEFAULT '',
        pack_type         TEXT NOT NULL DEFAULT '',
        spirit_style      TEXT NOT NULL DEFAULT '',
        whisky_style      TEXT NOT NULL DEFAULT '',
        vendor_name       TEXT NOT NULL DEFAULT '',
        vendor_id         TEXT NOT NULL DEFAULT '',
        overall_rating    REAL NOT NULL DEFAULT 0,
        number_of_reviews INTEGER NOT NULL DEFAULT 0,
        is_vegan          INTEGER NOT NULL DEFAULT 0,
        is_gluten_free    INTEGER NOT NULL DEFAULT 0,
        food_match        TEXT NOT NULL DEFAULT '',
        winemaker         TEXT NOT NULL DEFAULT '',
        award_winner      TEXT NOT NULL DEFAULT '',
        is_new            INTEGER NOT NULL DEFAULT 0,
        is_featured_tag   INTEGER NOT NULL DEFAULT 0,
        is_for_delivery   INTEGER NOT NULL DEFAULT 0,
        is_for_collection INTEGER NOT NULL DEFAULT 0,
        is_pre_sale       INTEGER NOT NULL DEFAULT 0,
        is_coming_soon    INTEGER NOT NULL DEFAULT 0,
        supply_limit      INTEGER NOT NULL DEFAULT 9999,
        minimum_quantity  INTEGER NOT NULL DEFAULT 1,
        display_quantity  INTEGER NOT NULL DEFAULT 1,
        inventory         TEXT NOT NULL DEFAULT '{}',
        info_message      TEXT NOT NULL DEFAULT '{}',
        alc_vol_message   TEXT NOT NULL DEFAULT '{}',
        usp               TEXT NOT NULL DEFAULT '[]',
        last_refreshed    TEXT,
        power_score       REAL NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('CREATE INDEX idx_p_brand ON products(brand)');
    await db.execute('CREATE INDEX idx_p_country ON products(country)');
    await db.execute(
      'CREATE INDEX idx_p_review_count ON products(review_count)',
    );

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
    await db.execute(
      'CREATE INDEX idx_ph_stockcode ON price_history(stockcode)',
    );

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
      await db.execute(
        "ALTER TABLE products ADD COLUMN backorder_stock INTEGER NOT NULL DEFAULT 0",
      );
      await db.execute(
        "ALTER TABLE products ADD COLUMN backorder_message TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE products ADD COLUMN is_delivery_only INTEGER NOT NULL DEFAULT 0",
      );
      await db.execute(
        "ALTER TABLE products ADD COLUMN is_edr_special INTEGER NOT NULL DEFAULT 0",
      );
      await db.execute(
        "ALTER TABLE products ADD COLUMN is_find_me_avail INTEGER NOT NULL DEFAULT 0",
      );
      await db.execute(
        "ALTER TABLE products ADD COLUMN age_restricted INTEGER NOT NULL DEFAULT 0",
      );
      await db.execute(
        "ALTER TABLE products ADD COLUMN unit TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE products ADD COLUMN pkg_size_display TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE products ADD COLUMN parent_stockcode TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE products ADD COLUMN source TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE products ADD COLUMN available_pack_types TEXT NOT NULL DEFAULT '[]'",
      );
      await db.execute(
        "ALTER TABLE products ADD COLUMN product_type TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE products ADD COLUMN main_category TEXT NOT NULL DEFAULT ''",
      );
    }
    // v2→v3: ensure product_type/main_category exist (some v2 DBs built without them)
    if (oldVersion < 3) {
      try {
        await db.execute(
          "ALTER TABLE products ADD COLUMN product_type TEXT NOT NULL DEFAULT ''",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE products ADD COLUMN main_category TEXT NOT NULL DEFAULT ''",
        );
      } catch (_) {}
    }
    // v3→v4: min_price for unit-price sorting
    if (oldVersion < 4) {
      try {
        await db.execute(
          "ALTER TABLE products ADD COLUMN min_price REAL NOT NULL DEFAULT 0",
        );
        // Compute min_price from existing price JSON (excludes Case packs)
        await db.rawUpdate(
          "UPDATE products SET min_price = COALESCE("
          "(SELECT MIN(CAST(json_extract(value, '\$.value') AS REAL)) "
          "FROM json_each(prices) "
          "WHERE CAST(json_extract(value, '\$.value') AS REAL) > 0 "
          "AND json_extract(value, '\$.packType') != 'Case'), 0)",
        );
      } catch (_) {}
    }
    // v4→v5: all scraper fields
    if (oldVersion < 5) {
      final cols = [
        "url_friendly_name TEXT NOT NULL DEFAULT ''",
        "pack_type TEXT NOT NULL DEFAULT ''",
        "spirit_style TEXT NOT NULL DEFAULT ''",
        "whisky_style TEXT NOT NULL DEFAULT ''",
        "vendor_name TEXT NOT NULL DEFAULT ''",
        "vendor_id TEXT NOT NULL DEFAULT ''",
        "overall_rating REAL NOT NULL DEFAULT 0",
        "number_of_reviews INTEGER NOT NULL DEFAULT 0",
        "is_vegan INTEGER NOT NULL DEFAULT 0",
        "is_gluten_free INTEGER NOT NULL DEFAULT 0",
        "food_match TEXT NOT NULL DEFAULT ''",
        "winemaker TEXT NOT NULL DEFAULT ''",
        "award_winner TEXT NOT NULL DEFAULT ''",
        "is_new INTEGER NOT NULL DEFAULT 0",
        "is_featured_tag INTEGER NOT NULL DEFAULT 0",
        "is_for_delivery INTEGER NOT NULL DEFAULT 0",
        "is_for_collection INTEGER NOT NULL DEFAULT 0",
        "is_pre_sale INTEGER NOT NULL DEFAULT 0",
        "is_coming_soon INTEGER NOT NULL DEFAULT 0",
        "supply_limit INTEGER NOT NULL DEFAULT 9999",
        "minimum_quantity INTEGER NOT NULL DEFAULT 1",
        "display_quantity INTEGER NOT NULL DEFAULT 1",
        "inventory TEXT NOT NULL DEFAULT '{}'",
        "info_message TEXT NOT NULL DEFAULT '{}'",
        "alc_vol_message TEXT NOT NULL DEFAULT '{}'",
        "usp TEXT NOT NULL DEFAULT '[]'",
      ];
      for (final c in cols) {
        try {
          await db.execute("ALTER TABLE products ADD COLUMN $c");
        } catch (_) {}
      }
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
      'product_type': (json['productType'] ?? '').toString(),
      'main_category': (json['mainCategory'] ?? '').toString(),
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

  /// Filter-only search (no text query) — uses SQL WHERE on populated fields
  Future<List<Product>> searchByFilter({
    List<String> countries = const [],
    List<String> categories = const [],
    List<String> regions = const [],
    List<String> tags = const [],
    bool inStockOnly = false,
    bool newOnly = false,
    bool hideUnavailable = false,
    int limit = 200,
    int offset = 0,
    String sortField = 'review_count',
    String sortDir = 'DESC',
  }) async {
    final conditions = <String>[];
    final args = <dynamic>[];

    if (countries.isNotEmpty) {
      final likes = countries.map((c) => 'country LIKE ?').join(' OR ');
      conditions.add('($likes)');
      args.addAll(countries.map((c) => '%$c%'));
    }
    // Categories: exact match on varietal, product_type, or main_category
    if (categories.isNotEmpty) {
      final likes = <String>[];
      for (final c in categories) {
        likes.add('(varietal = ? OR product_type = ? OR main_category = ?)');
        args.addAll([c, c, c]);
      }
      conditions.add('(${likes.join(' OR ')})');
    }
    if (regions.isNotEmpty) {
      final likes = regions.map((r) => 'region LIKE ?').join(' OR ');
      conditions.add('($likes)');
      args.addAll(regions.map((r) => '%$r%'));
    }
    if (inStockOnly) {
      conditions.add('stock_on_hand > 0');
    }
    if (hideUnavailable) {
      conditions.add('min_price > 0');
    }
    if (newOnly) {
      conditions.add('is_new = 1');
    }
    if (tags.isNotEmpty) {
      for (final tag in tags) {
        conditions.add("product_tags LIKE '%__${tag}.png%'");
      }
    }

    // Map sort field to SQL column
    String orderBy;
    switch (sortField) {
      case 'price':
        // Sort by min_price (individual unit price, no cases) — push $0 to end
        orderBy =
            "CASE WHEN min_price <= 0 THEN 1 ELSE 0 END, min_price $sortDir";
        break;
      case 'title':
        orderBy = "title $sortDir";
        break;
      case 'stock_on_hand':
        orderBy = "stock_on_hand $sortDir";
        break;
      case 'review_count':
        orderBy = "review_count $sortDir";
        break;
      case 'power_score':
        orderBy = "power_score $sortDir";
        break;
      default:
        orderBy = "review_count $sortDir";
        break;
    }

    final where = conditions.isNotEmpty
        ? 'WHERE ${conditions.join(' AND ')}'
        : '';
    final sql =
        'SELECT * FROM products $where ORDER BY $orderBy LIMIT $limit OFFSET $offset';
    final rows = await _db!.rawQuery(sql, args);
    if (categories.isNotEmpty) {
      final codes = rows.map((r) => r['stockcode']).take(5).join(', ');
      print(
        '[FILTER] cats=$categories sort=$sortField $sortDir -> first 5: $codes',
      );
    }
    return rows.map((r) => _rowToProduct(r)).toList();
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

  /// Check if product needs refresh (>24h since last_refreshed)
  Future<bool> shouldRefresh(String stockcode) async {
    final rows = await _db!.rawQuery(
      "SELECT last_refreshed FROM products WHERE stockcode = ?",
      [stockcode],
    );
    if (rows.isEmpty) return true;
    final lr = rows.first['last_refreshed'] as String?;
    if (lr == null || lr.isEmpty) return true;
    final last = DateTime.tryParse(lr);
    if (last == null) return true;
    return DateTime.now().difference(last).inHours >= 22;
  }

  /// Update product with fresh API data
  Future<void> markRefreshed(String stockcode) async {
    await _db!.rawUpdate(
      "UPDATE products SET last_refreshed = ? WHERE stockcode = ?",
      [DateTime.now().toIso8601String(), stockcode],
    );
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
      productType: row['product_type'] as String? ?? '',
      mainCategory: row['main_category'] as String? ?? '',
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
      availablePackTypes: _parseJsonList(
        row['available_pack_types'] as String?,
      ),
      backorderMessage: row['backorder_message'] as String? ?? '',
      isDeliveryOnly: row['is_delivery_only'] == 1,
      isEdrSpecial: row['is_edr_special'] == 1,
      isFindMeAvailable: row['is_find_me_avail'] == 1,
      ageRestricted: row['age_restricted'] == 1,
      unit: row['unit'] as String? ?? '',
      packageSizeDisplay: row['pkg_size_display'] as String? ?? '',
      parentStockCode: row['parent_stockcode'] as String? ?? '',
      source: row['source'] as String? ?? '',
      firstSeen: row['first_seen'] != null
          ? DateTime.tryParse(row['first_seen'] as String)
          : null,
    );
  }

  /// Close the database
  Future<void> close() async {
    await _db?.close();
    _ready = false;
  }
}
