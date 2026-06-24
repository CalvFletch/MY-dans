import '../models/product.dart';

class ProductFilters {
  double? minPrice;
  double? maxPrice;
  int? minVintage;
  int? maxVintage;
  double? minAlcohol;
  double? maxAlcohol;
  double? minPricePerLiter;
  double? maxPricePerLiter;
  final Set<String> countries = {};
  final Set<String> regions = {};
  final Set<String> categories = {};
  final Set<String> tags = {};
  bool inStockOnly = false;
  bool hideOnline = false;
  bool categoryAnd = false; // true=AND, false=OR
  bool countryAnd = false; // true=AND, false=OR
  bool newOnly = false;
  bool hideUnavailable = false;

  bool get isActive =>
      minPrice != null ||
      maxPrice != null ||
      minVintage != null ||
      maxVintage != null ||
      minAlcohol != null ||
      maxAlcohol != null ||
      minPricePerLiter != null ||
      maxPricePerLiter != null ||
      countries.isNotEmpty ||
      regions.isNotEmpty ||
      categories.isNotEmpty ||
      tags.isNotEmpty ||
      tags.isNotEmpty ||
      inStockOnly ||
      hideOnline ||
      newOnly ||
      hideUnavailable;

  void clear() {
    minPrice = maxPrice = null;
    minVintage = maxVintage = null;
    minAlcohol = maxAlcohol = null;
    minPricePerLiter = maxPricePerLiter = null;
    countries.clear();
    regions.clear();
    categories.clear();
    tags.clear();
    inStockOnly = false;
    hideOnline = false;
    categoryAnd = false;
    countryAnd = false;
    newOnly = false;
  }

  List<Product> apply(List<Product> products) {
    if (!isActive) return products;
    return products.where((p) {
      final price = p.singlePrice?.value ?? 0;
      if (minPrice != null && price < minPrice!) return false;
      if (maxPrice != null && price > maxPrice!) return false;
      if (inStockOnly && p.stockOnHand <= 0) return false;
      if (hideOnline && p.stockcode.startsWith('ER_')) return false;
      if (newOnly && !p.isNew) return false;
      if (tags.isNotEmpty) {
        final productTagNames = p.allBadges
            .where((b) => b['FallbackText'] != null)
            .map((b) => b['FallbackText'].toString().toLowerCase())
            .toSet();
        final productTagUrls = p.allBadges
            .where((b) => b['TagContent'] != null)
            .map((b) => b['TagContent'].toString().toLowerCase())
            .toSet();
        final hasMatch = tags.any(
          (t) =>
              productTagNames.contains(t.toLowerCase()) ||
              productTagUrls.any((u) => u.contains(t.toLowerCase())),
        );
        if (!hasMatch) return false;
      }

      final vintage = int.tryParse(p.vintage);
      if (minVintage != null && (vintage == null || vintage < minVintage!)) {
        return false;
      }
      if (maxVintage != null && (vintage == null || vintage > maxVintage!)) {
        return false;
      }

      final alcohol = double.tryParse(
        p.alcoholVolume.replaceAll('%', '').trim(),
      );
      if (minAlcohol != null && (alcohol == null || alcohol < minAlcohol!)) {
        return false;
      }
      if (maxAlcohol != null && (alcohol == null || alcohol > maxAlcohol!)) {
        return false;
      }

      if (minPricePerLiter != null || maxPricePerLiter != null) {
        final ppl = _pricePerLiter(p);
        if (ppl == null) return false;
        if (minPricePerLiter != null && ppl < minPricePerLiter!) return false;
        if (maxPricePerLiter != null && ppl > maxPricePerLiter!) return false;
      }

      if (countries.isNotEmpty) {
        final matches = countryAnd
            ? countries.every(
                (c) => p.country.toLowerCase().contains(c.toLowerCase()),
              )
            : countries.any(
                (c) => p.country.toLowerCase().contains(c.toLowerCase()),
              );
        if (!matches) return false;
      }

      if (regions.isNotEmpty) {
        final matches = regions.any(
          (r) =>
              '${p.region} ${p.state}'.toLowerCase().contains(r.toLowerCase()),
        );
        if (!matches) return false;
      }

      if (categories.isNotEmpty) {
        final matches = categoryAnd
            ? categories.every(
                (cat) =>
                    p.categories.any(
                      (pc) => pc.toLowerCase().contains(cat.toLowerCase()),
                    ) ||
                    p.title.toLowerCase().contains(cat.toLowerCase()) ||
                    p.varietal.toLowerCase().contains(cat.toLowerCase()),
              )
            : categories.any(
                (cat) =>
                    p.categories.any(
                      (pc) => pc.toLowerCase().contains(cat.toLowerCase()),
                    ) ||
                    p.title.toLowerCase().contains(cat.toLowerCase()) ||
                    p.varietal.toLowerCase().contains(cat.toLowerCase()),
              );
        if (!matches) return false;
      }

      return true;
    }).toList();
  }

  static double? _pricePerLiter(Product p) {
    final size = p.packageSize.toLowerCase().replaceAll(
      RegExp(r'[^0-9.ml]'),
      '',
    );
    double ml = 0;
    if (size.contains('l') && !size.contains('ml')) {
      ml = (double.tryParse(size.replaceAll('l', '')) ?? 0) * 1000;
    } else {
      ml = double.tryParse(size.replaceAll('ml', '')) ?? 0;
    }
    if (ml <= 0) return null;
    final promo = p.promoPrice;
    final single = p.singlePrice;
    final price = promo ?? single;
    if (price == null || price.value <= 0) return null;

    // Pack quantity: API AvailablePackTypes > message parsing > default
    int qty = p.packQtyForType(price.packType);
    if (qty <= 1) {
      final qtyMatch = RegExp(r'\((\d+)\)').firstMatch(price.message);
      if (qtyMatch != null) {
        qty = int.tryParse(qtyMatch.group(1)!) ?? 1;
      } else if (price.packType.toLowerCase() == 'case') {
        qty = 12;
      }
      final msg = price.message.toLowerCase();
      if (msg.contains('any six') || msg.contains('any 6')) qty = 6;
    }

    return price.value / ((ml * qty) / 1000);
  }
}
