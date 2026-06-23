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
  bool inStockOnly = false;
  bool hideOnline = false;
  bool categoryAnd = false; // true=AND, false=OR
  bool countryAnd = false; // true=AND, false=OR
  bool newOnly = false;

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
      inStockOnly ||
      hideOnline ||
      newOnly;

  void clear() {
    minPrice = maxPrice = null;
    minVintage = maxVintage = null;
    minAlcohol = maxAlcohol = null;
    minPricePerLiter = maxPricePerLiter = null;
    countries.clear();
    regions.clear();
    categories.clear();
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

      final vintage = int.tryParse(p.vintage);
      if (minVintage != null && (vintage == null || vintage < minVintage!))
        return false;
      if (maxVintage != null && (vintage == null || vintage > maxVintage!))
        return false;

      final alcohol = double.tryParse(
        p.alcoholVolume.replaceAll('%', '').trim(),
      );
      if (minAlcohol != null && (alcohol == null || alcohol < minAlcohol!))
        return false;
      if (maxAlcohol != null && (alcohol == null || alcohol > maxAlcohol!))
        return false;

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
    final price = p.singlePrice?.value ?? 0;
    if (price <= 0) return null;
    return price / (ml / 1000);
  }
}
