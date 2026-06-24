class PriceRecord {
  final DateTime date;
  final double value;
  final String type;

  PriceRecord({required this.date, required this.value, this.type = ''});

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'value': value,
    'type': type,
  };

  factory PriceRecord.fromJson(Map<String, dynamic> json) => PriceRecord(
    date: DateTime.parse(json['date'] as String),
    value: (json['value'] as num).toDouble(),
    type: (json['type'] ?? '').toString(),
  );
}

class Product {
  final String stockcode;
  final String title;
  final String brand;
  final String description;
  final String richDescription;
  final String packageSize;
  final String alcoholVolume;
  final String varietal;
  final String region;
  final String state;
  final String country;
  final String vintage;
  final String closure;
  final String standardDrinks;
  final String wineBody;
  final String wineSweetness;
  final String productType;
  final String mainCategory;
  final double? averageRating;
  final int totalReviewCount;
  final List<ProductPrice> prices;
  final int stockOnHand;
  final bool isPurchasable;
  final bool isOnSpecial;
  final bool isMemberSpecial;
  final List<String> categories;
  final List<String> previousTitles;
  final List<PriceRecord> priceHistory;
  final DateTime? firstSeen;
  final DateTime? lastPriceRefresh;   // when prices/stock last fetched live
  final DateTime? lastDetailRefresh;  // when full detail last fetched
  final List<Map<String, dynamic>> productTags;
  final List<Map<String, dynamic>> productSashes;
  final List<Map<String, dynamic>> availablePackTypes;
  final String backorderMessage;
  final bool isDeliveryOnly;
  final bool isEdrSpecial;
  final bool isFindMeAvailable;
  final bool ageRestricted;
  final String unit;
  final String packageSizeDisplay;
  final String parentStockCode;
  final List<Map<String, dynamic>> productsInSameOffer;
  final List<Map<String, dynamic>> recommendedProducts;
  final String source;
  final List<Map<String, dynamic>> deliveryOptionsInfo;

  /// Get pack quantity for a given pack type (e.g., "Case" → 24, "Bottle" → 1)
  int packQtyForType(String packType) {
    for (final apt in availablePackTypes) {
      if ((apt['Key'] ?? '').toString().toLowerCase() ==
          packType.toLowerCase()) {
        return apt['UnitQty'] as int? ?? 1;
      }
    }
    return 1; // fallback
  }

  /// True if product was first seen within the last 90 days
  bool get isNew =>
      firstSeen != null && DateTime.now().difference(firstSeen!).inDays <= 90;

  /// Derived badges computed from product attributes (like Zero% Alcohol)
  List<Map<String, dynamic>> get derivedBadges {
    final badges = <Map<String, dynamic>>[];
    final abv = double.tryParse(alcoholVolume.replaceAll('%', '').trim());
    if (abv != null && abv <= 0.5 && alcoholVolume.isNotEmpty) {
      badges.add({
        'TagContent':
            'https://media.danmurphys.com.au/dmo/e-commerce/badges/DM_Badges_Working_CMYK__Zero-_%20Alcohol.png',
        'FallbackText': 'Zero%* Alcohol 0-0.5% ABV',
        'TagType': 'Derived',
      });
    }
    return badges;
  }

  List<Map<String, dynamic>> get allBadges => [
    ...productTags,
    ...derivedBadges,
  ];

  Product({
    required this.stockcode,
    required this.title,
    required this.brand,
    required this.description,
    required this.richDescription,
    required this.packageSize,
    required this.alcoholVolume,
    required this.varietal,
    required this.region,
    required this.state,
    required this.country,
    required this.vintage,
    required this.closure,
    required this.standardDrinks,
    required this.wineBody,
    required this.wineSweetness,
    this.productType = '',
    this.mainCategory = '',
    this.averageRating,
    this.totalReviewCount = 0,
    required this.prices,
    this.stockOnHand = 0,
    this.isPurchasable = true,
    this.isOnSpecial = false,
    this.isMemberSpecial = false,
    this.categories = const [],
    this.previousTitles = const [],
    this.priceHistory = const [],
    this.firstSeen,
    this.lastPriceRefresh,
    this.lastDetailRefresh,
    this.productTags = const [],
    this.productSashes = const [],
    this.availablePackTypes = const [],
    this.backorderMessage = '',
    this.isDeliveryOnly = false,
    this.isEdrSpecial = false,
    this.isFindMeAvailable = false,
    this.ageRestricted = false,
    this.unit = '',
    this.packageSizeDisplay = '',
    this.parentStockCode = '',
    this.productsInSameOffer = const [],
    this.recommendedProducts = const [],
    this.source = '',
    this.deliveryOptionsInfo = const [],
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    final additionalDetails =
        (json['AdditionalDetails'] as List<dynamic>?) ?? [];
    String ad(String name) =>
        (additionalDetails.firstWhere(
                  (d) => d['Name'] == name,
                  orElse: () => {'Value': ''},
                )['Value'] ??
                '')
            .toString();

    final prices = (json['Prices'] as Map<String, dynamic>?) ?? {};
    final priceList = <ProductPrice>[];
    for (final entry in prices.entries) {
      final p = entry.value as Map<String, dynamic>?;
      if (p != null) {
        priceList.add(
          ProductPrice(
            type: entry.key,
            message: (p['Message'] ?? '').toString(),
            value: (p['Value'] ?? 0).toDouble(),
            preText: (p['PreText'] ?? '').toString(),
            isMemberOffer: p['IsMemberOffer'] == true,
            packType: (p['PackType'] ?? '').toString(),
            beforePromotion: (p['BeforePromotion'] ?? 0).toDouble(),
            afterPromotion: (p['AfterPromotion'] ?? 0).toDouble(),
          ),
        );
      }
    }

    final categories =
        (json['Categories'] as List<dynamic>?)
            ?.map((c) => (c['Name'] ?? '').toString())
            .toList() ??
        [];

    // Extract image numbers from GroupedDetails
    final groupedImages =
        (json['GroupedDetails']?['image'] as List<dynamic>?) ?? [];
    final variants = <String>[];
    for (final img in groupedImages) {
      final val = (img['Value'] ?? '').toString();
      if (val.isNotEmpty) variants.add(val.replaceAll('.png', ''));
    }

    return Product(
      stockcode: (json['Stockcode'] ?? '').toString(),
      title: ad('webtitle'),
      brand: ad('webbrandname'),
      description: (json['Description'] ?? '').toString(),
      richDescription: (json['RichDescription'] ?? '').toString(),
      packageSize: ad('webliquorsize'),
      alcoholVolume: ad('webalcoholpercentage'),
      varietal: ad('varietal'),
      region: ad('webregionoforigin'),
      state: ad('webstateoforigin'),
      country: ad('countryoforigin'),
      vintage: ad('webvintagecurrent'),
      closure: ad('webbottleclosure'),
      standardDrinks: ad('standarddrinks'),
      wineBody: ad('webwinebody'),
      wineSweetness: ad('webwinestyle'),
      averageRating: double.tryParse(ad('webaverageproductrating')),
      totalReviewCount: int.tryParse(ad('webtotalreviewcount')) ?? 0,
      prices: priceList,
      stockOnHand: json['StockOnHand'] ?? 0,
      isPurchasable: json['IsPurchasable'] == true,
      isOnSpecial: json['IsOnSpecial'] == true,
      isMemberSpecial: json['IsMemberSpecial'] == true,
      categories: categories,
      previousTitles:
          (json['previousTitles'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      priceHistory:
          (json['priceHistory'] as List<dynamic>?)
              ?.map((e) => PriceRecord.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      firstSeen: json['firstSeen'] != null
          ? DateTime.tryParse(json['firstSeen'].toString())
          : null,
      lastPriceRefresh: json['lastPriceRefresh'] != null
          ? DateTime.tryParse(json['lastPriceRefresh'].toString())
          : null,
      lastDetailRefresh: json['lastDetailRefresh'] != null
          ? DateTime.tryParse(json['lastDetailRefresh'].toString())
          : null,
      productTags:
          (json['productTags'] as List<dynamic>?)
              ?.map(
                (e) => e is Map
                    ? Map<String, dynamic>.from(e)
                    : <String, dynamic>{},
              )
              .toList() ??
          [],
      productSashes:
          (json['productSashes'] as List<dynamic>?)
              ?.map(
                (e) => e is Map
                    ? Map<String, dynamic>.from(e)
                    : <String, dynamic>{},
              )
              .toList() ??
          [],
      availablePackTypes:
          (json['availablePackTypes'] as List<dynamic>?)
              ?.map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{})
              .toList() ??
          [],
      backorderMessage: (json['backorderMessage'] ?? '').toString(),
      isDeliveryOnly: json['isDeliveryOnly'] == true,
      isEdrSpecial: json['isEdrSpecial'] == true,
      isFindMeAvailable: json['isFindMeAvailable'] == true,
      ageRestricted: json['ageRestricted'] == true,
      unit: (json['unit'] ?? '').toString(),
      packageSizeDisplay: (json['packageSizeDisplay'] ?? '').toString(),
      parentStockCode: (json['parentStockCode'] ?? '').toString(),
      productsInSameOffer:
          (json['productsInSameOffer'] as List<dynamic>?)
              ?.map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{})
              .toList() ??
          [],
      recommendedProducts:
          (json['recommendedProducts'] as List<dynamic>?)
              ?.map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{})
              .toList() ??
          [],
      source: (json['source'] ?? '').toString(),
      deliveryOptionsInfo:
          (json['deliveryOptionsInfo'] as List<dynamic>?)
              ?.map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{})
              .toList() ??
          [],
    );
  }

  String get cdnImageUrl =>
      'https://media.danmurphys.com.au/dmo/product/$stockcode-1.png?impolicy=PROD_MD';

  String get cdnImageLargeUrl =>
      'https://media.danmurphys.com.au/dmo/product/$stockcode-1.png?impolicy=PROD_LG';

  String cdnImageVariant(int index) =>
      'https://media.danmurphys.com.au/dmo/product/$stockcode-$index.png?impolicy=PROD_LG';

  ProductPrice? get promoPrice {
    try {
      return prices.firstWhere(
        (p) => p.isMemberOffer || p.type == 'promoprice',
      );
    } catch (_) {
      return null;
    }
  }

  ProductPrice? get singlePrice {
    try {
      return prices.firstWhere((p) => p.type == 'singleprice');
    } catch (_) {
      return prices.isNotEmpty ? prices.first : null;
    }
  }

  /// Create from AdvertisedOffers JSON (lightweight, for cache)
  factory Product.fromOfferJson(Map<String, dynamic> json) {
    final prices = <ProductPrice>[];
    final priceList = json['prices'] as List<dynamic>? ?? [];
    for (final p in priceList) {
      final pm = p as Map<String, dynamic>;
      prices.add(
        ProductPrice(
          type: (pm['type'] ?? '').toString(),
          message: (pm['message'] ?? '').toString(),
          value: (pm['value'] ?? 0).toDouble(),
          preText: (pm['preText'] ?? '').toString(),
          isMemberOffer: pm['isMemberOffer'] == true,
          packType: (pm['packType'] ?? '').toString(),
          beforePromotion: (pm['beforePromotion'] ?? 0).toDouble(),
          afterPromotion: (pm['afterPromotion'] ?? 0).toDouble(),
        ),
      );
    }

    final imageVariants =
        (json['imageVariants'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final categories =
        (json['categories'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    return Product(
      stockcode: (json['stockcode'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      brand: (json['brand'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      richDescription: (json['richDescription'] ?? '').toString(),
      packageSize: (json['packageSize'] ?? '').toString(),
      alcoholVolume: (json['alcoholVolume'] ?? '').toString(),
      varietal: (json['varietal'] ?? '').toString(),
      region: (json['region'] ?? '').toString(),
      state: (json['state'] ?? '').toString(),
      country: (json['country'] ?? '').toString(),
      vintage: (json['vintage'] ?? '').toString(),
      closure: (json['closure'] ?? '').toString(),
      standardDrinks: (json['standardDrinks'] ?? '').toString(),
      wineBody: (json['wineBody'] ?? '').toString(),
      wineSweetness: (json['wineSweetness'] ?? '').toString(),
      productType: (json['productType'] ?? '').toString(),
      mainCategory: (json['mainCategory'] ?? '').toString(),
      averageRating: (json['averageRating'] as num?)?.toDouble(),
      totalReviewCount: json['totalReviewCount'] ?? 0,
      prices: prices,
      stockOnHand: json['stockOnHand'] ?? 0,
      isPurchasable: json['isPurchasable'] != false,
      isOnSpecial: json['isOnSpecial'] == true,
      isMemberSpecial: json['isMemberSpecial'] == true,
      categories: categories,
      previousTitles:
          (json['previousTitles'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      priceHistory:
          (json['priceHistory'] as List<dynamic>?)
              ?.map((e) => PriceRecord.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      firstSeen: json['firstSeen'] != null
          ? DateTime.tryParse(json['firstSeen'].toString())
          : null,
      lastPriceRefresh: json['lastPriceRefresh'] != null
          ? DateTime.tryParse(json['lastPriceRefresh'].toString())
          : null,
      lastDetailRefresh: json['lastDetailRefresh'] != null
          ? DateTime.tryParse(json['lastDetailRefresh'].toString())
          : null,
      productTags:
          (json['productTags'] as List<dynamic>?)
              ?.map(
                (e) => e is Map
                    ? Map<String, dynamic>.from(e)
                    : <String, dynamic>{},
              )
              .toList() ??
          [],
      productSashes:
          (json['productSashes'] as List<dynamic>?)
              ?.map(
                (e) => e is Map
                    ? Map<String, dynamic>.from(e)
                    : <String, dynamic>{},
              )
              .toList() ??
          [],
      availablePackTypes:
          (json['availablePackTypes'] as List<dynamic>?)
              ?.map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{})
              .toList() ??
          [],
      backorderMessage: (json['backorderMessage'] ?? '').toString(),
      isDeliveryOnly: json['isDeliveryOnly'] == true,
      isEdrSpecial: json['isEdrSpecial'] == true,
      isFindMeAvailable: json['isFindMeAvailable'] == true,
      ageRestricted: json['ageRestricted'] == true,
      unit: (json['unit'] ?? '').toString(),
      packageSizeDisplay: (json['packageSizeDisplay'] ?? '').toString(),
      parentStockCode: (json['parentStockCode'] ?? '').toString(),
      productsInSameOffer: const [],
      recommendedProducts: const [],
      source: '',
      deliveryOptionsInfo: const [],
    );
  }

  /// Create from web search results JSON
  factory Product.fromSearchJson(Map<String, dynamic> json) {
    final name = (json['Name'] ?? '')
        .toString()
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .trim();
    final rawCode =
        (json['PackDefaultStockCode'] ?? json['PackParentStockCode'] ?? '')
            .toString();
    // Strip URL slug suffix like _PEN28-2013GB-750ML-1
    final stockcode = rawCode.replaceFirst(RegExp(r'_[A-Z]+\d+.*$'), '');
    final nestedProducts = json['Products'] as List<dynamic>? ?? [];
    final first = nestedProducts.isNotEmpty
        ? nestedProducts[0] as Map<String, dynamic>?
        : null;

    final prices = <ProductPrice>[];
    if (first != null) {
      final priceMap = first['Prices'] as Map<String, dynamic>? ?? {};
      for (final entry in priceMap.entries) {
        final p = entry.value as Map<String, dynamic>?;
        if (p != null) {
          prices.add(
            ProductPrice(
              type: entry.key,
              message: (p['Message'] ?? '').toString(),
              value: (p['Value'] ?? 0).toDouble(),
              preText: (p['PreText'] ?? '').toString(),
              isMemberOffer: p['IsMemberOffer'] == true,
              packType: (p['PackType'] ?? '').toString(),
              beforePromotion: (p['BeforePromotion'] ?? 0).toDouble(),
              afterPromotion: (p['AfterPromotion'] ?? 0).toDouble(),
            ),
          );
        }
      }
    }

    final inv = first?['Inventory'] as Map<String, dynamic>?;
    final stockOnHand = inv?['availableinventoryqty'] ?? 0;

    // Parse AdditionalDetails — handles both List and Map formats
    final adRaw = first?['AdditionalDetails'];
    String ad(String n) {
      if (adRaw is List) {
        for (final d in adRaw) {
          if (d is Map && d['Name'] == n) return (d['Value'] ?? '').toString();
        }
      } else if (adRaw is Map) {
        return (adRaw[n] ?? '').toString();
      }
      return '';
    }

    return Product(
      stockcode: stockcode,
      title: name,
      brand: ad('webbrandname'),
      description: (first?['Description'] ?? '').toString(),
      richDescription: (first?['RichDescription'] ?? '').toString(),
      packageSize: ad('webliquorsize'),
      alcoholVolume: ad('webalcoholpercentage'),
      varietal: ad('varietal'),
      region: ad('webregionoforigin'),
      state: ad('webstateoforigin'),
      country: ad('countryoforigin'),
      vintage: ad('webvintagecurrent'),
      closure: ad('webbottleclosure'),
      standardDrinks: ad('standarddrinks'),
      wineBody: ad('webwinebody'),
      wineSweetness: ad('webwinestyle'),
      averageRating: double.tryParse(ad('webaverageproductrating')),
      totalReviewCount: int.tryParse(ad('webtotalreviewcount')) ?? 0,
      prices: prices,
      stockOnHand: stockOnHand,
      isPurchasable: true,
      isOnSpecial: prices.any((p) => p.isMemberOffer),
      isMemberSpecial: false,
      categories: [],
      previousTitles:
          (json['previousTitles'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      priceHistory:
          (json['priceHistory'] as List<dynamic>?)
              ?.map((e) => PriceRecord.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      firstSeen: json['firstSeen'] != null
          ? DateTime.tryParse(json['firstSeen'].toString())
          : null,
      lastPriceRefresh: DateTime.now(),  // search result = fresh price data
      lastDetailRefresh: null,            // search result = partial, needs detail fetch
      backorderMessage: '',
      isDeliveryOnly: false,
      isEdrSpecial: false,
      isFindMeAvailable: false,
      ageRestricted: false,
      unit: '',
      packageSizeDisplay: '',
      parentStockCode: '',
      productsInSameOffer: const [],
      recommendedProducts: const [],
      source: '',
      deliveryOptionsInfo: const [],
    );
  }

  /// Serialize for cache
  Map<String, dynamic> toOfferJson() => {
    'stockcode': stockcode,
    'title': title,
    'brand': brand,
    'description': description,
    'richDescription': richDescription,
    'packageSize': packageSize,
    'alcoholVolume': alcoholVolume,
    'varietal': varietal,
    'region': region,
    'state': state,
    'country': country,
    'vintage': vintage,
    'closure': closure,
    'standardDrinks': standardDrinks,
    'wineBody': wineBody,
    'wineSweetness': wineSweetness,
    'averageRating': averageRating,
    'totalReviewCount': totalReviewCount,
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
    'stockOnHand': stockOnHand,
    'isPurchasable': isPurchasable,
    'isOnSpecial': isOnSpecial,
    'isMemberSpecial': isMemberSpecial,
    'categories': categories,
    'previousTitles': previousTitles,
    'priceHistory': priceHistory.map((p) => p.toJson()).toList(),
    if (firstSeen != null) 'firstSeen': firstSeen!.toIso8601String(),
    if (lastPriceRefresh != null) 'lastPriceRefresh': lastPriceRefresh!.toIso8601String(),
    if (lastDetailRefresh != null) 'lastDetailRefresh': lastDetailRefresh!.toIso8601String(),
    'backorderMessage': backorderMessage,
    'isDeliveryOnly': isDeliveryOnly,
    'isEdrSpecial': isEdrSpecial,
    'isFindMeAvailable': isFindMeAvailable,
    'ageRestricted': ageRestricted,
    'unit': unit,
    'packageSizeDisplay': packageSizeDisplay,
    'parentStockCode': parentStockCode,
    'productsInSameOffer': productsInSameOffer,
    'recommendedProducts': recommendedProducts,
    'source': source,
    'deliveryOptionsInfo': deliveryOptionsInfo,
  };

  Product copyWith({int? stockOnHand}) {
    return Product(
      stockcode: stockcode,
      title: title,
      brand: brand,
      description: description,
      richDescription: richDescription,
      packageSize: packageSize,
      alcoholVolume: alcoholVolume,
      varietal: varietal,
      region: region,
      state: state,
      country: country,
      vintage: vintage,
      closure: closure,
      standardDrinks: standardDrinks,
      wineBody: wineBody,
      wineSweetness: wineSweetness,
      productType: productType,
      mainCategory: mainCategory,
      averageRating: averageRating,
      totalReviewCount: totalReviewCount,
      prices: prices,
      stockOnHand: stockOnHand ?? this.stockOnHand,
      isPurchasable: isPurchasable,
      isOnSpecial: isOnSpecial,
      isMemberSpecial: isMemberSpecial,
      categories: categories,
      previousTitles: previousTitles,
      priceHistory: priceHistory,
      firstSeen: firstSeen,
      lastPriceRefresh: lastPriceRefresh,
      lastDetailRefresh: lastDetailRefresh,
      backorderMessage: backorderMessage,
      isDeliveryOnly: isDeliveryOnly,
      isEdrSpecial: isEdrSpecial,
      isFindMeAvailable: isFindMeAvailable,
      ageRestricted: ageRestricted,
      unit: unit,
      packageSizeDisplay: packageSizeDisplay,
      parentStockCode: parentStockCode,
      productsInSameOffer: productsInSameOffer,
      recommendedProducts: recommendedProducts,
      source: source,
      deliveryOptionsInfo: deliveryOptionsInfo,
    );
  }
}

class ProductPrice {
  final String type;
  final String message;
  final double value;
  final String preText;
  final bool isMemberOffer;
  final String packType;
  final double beforePromotion;
  final double afterPromotion;

  ProductPrice({
    required this.type,
    required this.message,
    required this.value,
    required this.preText,
    required this.isMemberOffer,
    required this.packType,
    required this.beforePromotion,
    required this.afterPromotion,
  });
}
