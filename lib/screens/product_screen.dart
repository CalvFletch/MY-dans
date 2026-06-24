import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../models/product.dart';
import '../services/search_service.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../widgets/store_sheet.dart';
import '../widgets/barcode_widget.dart';

class ProductScreen extends StatefulWidget {
  final String stockcode;
  const ProductScreen({super.key, required this.stockcode});
  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  Product? _p;
  bool _loading = true;
  String? _error;
  int _imgIdx = 0;
  List<String> _imgs = [];
  String _storeNo = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _storeNo = await CacheService.getStoreNo();
    try {
      final cached = SearchService.database[widget.stockcode];
      final p = await SearchService.hydrate(
        cached ??
            Product(
              stockcode: widget.stockcode,
              title: '',
              brand: '',
              description: '',
              richDescription: '',
              packageSize: '',
              alcoholVolume: '',
              varietal: '',
              region: '',
              state: '',
              country: '',
              vintage: '',
              closure: '',
              standardDrinks: '',
              wineBody: '',
              wineSweetness: '',
              prices: [],
              stockOnHand: 0,
              isPurchasable: false,
            ),
        storeNo: _storeNo,
      );
      if (!mounted) return;
      final urls = <String>[p.cdnImageLargeUrl];
      for (var i = 2; i <= 8; i++) {
        urls.add(p.cdnImageVariant(i));
      }
      setState(() {
        _p = p;
        _imgs = urls;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Load failed';
          _loading = false;
        });
      }
    }
  }

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _ProductHistoryPage(product: _p!)),
    );
  }

  void _openFullImage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullImageViewer(images: _imgs, initialIndex: _imgIdx),
      ),
    );
  }

  void _openOtherStores() async {
    final postcode = await CacheService.getPostcode();
    final storeName = await CacheService.getStoreName();
    if (postcode.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => StoreSheet(
        stockcode: _p!.stockcode,
        postcode: postcode,
        refName: storeName.isNotEmpty ? storeName : null,
      ),
    );
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: _p!.stockcode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Code copied'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _copyPackCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$code copied'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Widget _buildPackVariants(Product p, bool isDark) {
    // Get unique pack types from prices
    final variants = <_PackVariant>[];
    final seen = <String>{};
    for (final pp in p.prices) {
      if (pp.value > 0 && pp.packType.isNotEmpty && seen.add(pp.packType)) {
        final label = pp.packType == 'Bottle' ? 'Each' : pp.packType;
        final qty = p.packQtyForType(pp.packType);
        variants.add(_PackVariant(
          label: label,
          price: pp.value,
          stockcode: p.stockcode,
          packType: pp.packType,
          qty: qty,
        ));
      }
    }

    if (variants.length <= 1) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pack sizes',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.grey[700]),
        ),
        const SizedBox(height: 6),
        ...variants.map((v) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isDark ? Colors.white24 : Colors.grey[300]!),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${v.label}${v.qty > 1 ? ' × $v.qty' : ''}',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: isDark ? Colors.white : Colors.black87),
                      ),
                      const SizedBox(height: 2),
                      GestureDetector(
                        onTap: () => _copyPackCode(v.stockcode),
                        onLongPress: () => BarcodeGenerator.show(context, v.stockcode),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(v.stockcode,
                              style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: isDark ? Colors.white54 : Colors.grey[500]),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.copy, size: 12, color: Colors.grey),
                            const SizedBox(width: 2),
                            const Icon(Icons.qr_code_2, size: 14, color: Colors.grey),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Text('\$${v.price.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
          ),
        )),
      ],
    );
  }

  Future<void> _openGoogle() async {
    final q = Uri.encodeComponent('${_p!.title} ${_p!.brand} Dan Murphy');
    await launchUrl(
      Uri.parse('https://www.google.com/search?q=$q'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _openDans() async {
    final code = _p!.stockcode;
    // Online-only products use ER_ prefix directly, others use DM_
    final prefix = code.startsWith('ER_') ? '' : 'DM_';
    await launchUrl(
      Uri.parse('https://www.danmurphys.com.au/product/$prefix$code'),
      mode: LaunchMode.externalApplication,
    );
  }

  void _searchBrand() {
    final brand = _p!.brand.trim();
    if (brand.isEmpty) return;
    Navigator.pop(context, brand);
  }

  /// Parse packageSize like "750ml" → mL, compute price per liter.
  /// Accounts for multipacks: case (24) × 330ml = 7.92L, not 0.33L.
  String? _pricePerLitre() {
    final p = _p!;
    final size = p.packageSize.toLowerCase().replaceAll(
      RegExp(r'[^0-9.ml]'),
      '',
    );
    double ml = 0;
    if (size.contains('l') && !size.contains('ml')) {
      ml = double.tryParse(size.replaceAll('l', '')) ?? 0;
      ml *= 1000;
    } else {
      ml = double.tryParse(size.replaceAll('ml', '')) ?? 0;
    }
    if (ml <= 0) return null;

    // Pick the best price: promo > single > first non-zero
    final promo = p.promoPrice;
    final single = p.singlePrice;
    final price = promo ?? single;
    if (price == null || price.value <= 0) return null;

    // Determine pack quantity: API AvailablePackTypes > message parsing > default
    int qty = p.packQtyForType(price.packType);
    if (qty <= 1) {
      // Fallback to message parsing
      final qtyMatch = RegExp(r'\((\d+)\)').firstMatch(price.message);
      if (qtyMatch != null) {
        qty = int.tryParse(qtyMatch.group(1)!) ?? 1;
      } else if (price.packType.toLowerCase() == 'case') {
        qty = 12;
      }
      final msg = price.message.toLowerCase();
      if (msg.contains('any six') || msg.contains('any 6')) qty = 6;
    }

    final totalMl = ml * qty;
    final perL = (price.value / (totalMl / 1000)).toStringAsFixed(2);
    return '\$$perL/L';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text(_p?.title ?? 'Loading...', overflow: TextOverflow.ellipsis),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          : _build(isDark),
    );
  }

  Widget _build(bool isDark) {
    final p = _p!;
    final promo = p.promoPrice;
    final price = p.singlePrice;
    final cardBg = isDark ? Theme.of(context).cardColor : Colors.white;
    final perLitre = _pricePerLitre();

    // All distinct pack types with prices
    final packVariants = <ProductPrice>[];
    final seenPacks = <String>{};
    for (final pp in p.prices) {
      if (pp.value > 0 && pp.packType.isNotEmpty && seenPacks.add(pp.packType)) {
        packVariants.add(pp);
      }
    }
    // Selected pack type (default: single/bottle)
    final selectedPack = packVariants.firstWhere(
      (pp) => pp.type == 'singleprice' || pp.packType == 'Bottle',
      orElse: () => packVariants.isNotEmpty ? packVariants.first : price!,
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_imgs.isNotEmpty)
            GestureDetector(
              onTap: _openFullImage,
              onHorizontalDragEnd: (d) {
                if (d.primaryVelocity! < -50 && _imgIdx < _imgs.length - 1) {
                  setState(() => _imgIdx++);
                } else if (d.primaryVelocity! > 50 && _imgIdx > 0)
                  setState(() => _imgIdx--);
              },
              child: Container(
                width: double.infinity,
                color: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    Image.network(
                      _imgs[_imgIdx],
                      height: 200,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => SizedBox(
                        height: 200,
                        child: const Center(
                          child: Icon(
                            Icons.wine_bar,
                            size: 48,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
                    if (_imgs.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            _imgs.length,
                            (i) => Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _imgIdx == i
                                    ? AppColors.primary
                                    : Colors.grey[300],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

          // Badge images (from API tags + derived)
          if (_p != null && _p!.allBadges.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _p!.allBadges
                    .where(
                      (b) =>
                          b['TagType'] == 'Image' || b['TagType'] == 'Derived',
                    )
                    .map(
                      (b) => Image.network(
                        (b['TagContent'] ?? '').toString(),
                        height: 48,
                        width: 48,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.highlight),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            (b['FallbackText'] ?? '').toString(),
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.highlight,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),

          // Member Offer sash
          if (_p != null && _p!.productSashes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: _p!.productSashes
                    .map(
                      (s) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.memberOfferBg,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          (s['TagContent'] ?? '').toString(),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.memberOfferDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title - tap to copy
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: p.title));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Title copied'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  child: Text(
                    p.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // Code
                GestureDetector(
                  onTap: _copyCode,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        p.stockcode,
                        style: TextStyle(
                          fontSize: 15,
                          fontFamily: 'monospace',
                          color: isDark ? Colors.white70 : Colors.grey[600],
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.copy, size: 16, color: Colors.grey),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // Brand
                InkWell(
                  onTap: _searchBrand,
                  child: Text(
                    p.brand,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? AppColors.memberOffer
                          : AppColors.memberOfferDark,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Pack variants with barcodes
                _buildPackVariants(p, isDark),

                const SizedBox(height: 12),
                // Icon buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: _openGoogle,
                      tooltip: 'Google search',
                      icon: const Icon(Icons.search, size: 24),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      onPressed: _openDans,
                      tooltip: 'Open on Dan Murphy\'s website',
                      icon: SvgPicture.asset(
                        'assets/original-dans-head-logo.svg',
                        height: 22,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Price card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: promo != null
                        ? (isDark
                              ? AppColors.memberOfferBgDark
                              : AppColors.memberOfferBg)
                        : (isDark
                              ? Theme.of(context).cardColor
                              : Colors.grey[50]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (promo != null &&
                              promo.beforePromotion > promo.afterPromotion) ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '\$${promo.beforePromotion.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    decoration: TextDecoration.lineThrough,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.grey[500],
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '\$${promo.afterPromotion.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? AppColors.memberOffer
                                        : AppColors.memberOfferDark,
                                  ),
                                ),
                                if (perLitre != null) ...[
                                  const SizedBox(width: 10),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      perLitre,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.grey[500],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.memberOfferDark.withAlpha(40)
                                    : AppColors.memberOfferDark.withAlpha(20),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                promo.message,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? AppColors.memberOffer
                                      : AppColors.memberOfferDark,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ] else ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '\$${(price?.value ?? 0).toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (perLitre != null) ...[
                                  const SizedBox(width: 10),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      perLitre,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.grey[500],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (price != null && price.message.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  price.message,
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.grey[600],
                                  ),
                                ),
                              ),
                          ],
                          if (p.prices.length > 1) ...[
                            const SizedBox(height: 10),
                            const Divider(),
                            ...p.prices
                                .where(
                                  (pr) =>
                                      pr.type != 'singleprice' &&
                                      pr.type != 'promoprice',
                                )
                                .map(
                                  (pr) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 3,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          pr.message,
                                          style: TextStyle(
                                            color: isDark
                                                ? Colors.white70
                                                : Colors.grey[700],
                                          ),
                                        ),
                                        Text(
                                          '\$${pr.value.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                          ],
                        ],
                      ),
                      // History button — top RIGHT
                      Positioned(
                        top: 0,
                        right: 0,
                        child: IconButton(
                          icon: const Icon(Icons.show_chart, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Price & stock history',
                          onPressed: _openHistory,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                // Stock above specs
                if (_storeNo.isNotEmpty) ...[
                  _section('Stock', Icons.inventory_2),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              p.isPurchasable
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              color: p.isPurchasable
                                  ? Colors.green
                                  : Colors.red,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${p.stockOnHand} units on hand',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    p.isPurchasable
                                        ? 'Available for delivery & collection'
                                        : 'Unavailable',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.white54
                                          : Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _openOtherStores,
                            icon: const Icon(Icons.store, size: 16),
                            label: const Text(
                              'Stock in nearby stores',
                              style: TextStyle(fontSize: 12),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isDark
                                  ? Colors.white70
                                  : AppColors.primary,
                              side: BorderSide(
                                color: isDark
                                    ? Colors.white24
                                    : AppColors.primary.withAlpha(60),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                _section('Product Details', Icons.info_outline),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      _row('Varietal', p.varietal, isDark),
                      _regionRow(p, isDark),
                      _row('Size', p.packageSize, isDark),
                      _row('Alcohol', p.alcoholVolume, isDark),
                      _row('Vintage', p.vintage, isDark),
                      _row('Closure', p.closure, isDark),
                      _row('Std Drinks', p.standardDrinks, isDark),
                      if (p.wineBody.isNotEmpty)
                        _row('Body', p.wineBody, isDark),
                      if (p.wineSweetness.isNotEmpty)
                        _row('Style', p.wineSweetness, isDark),
                    ],
                  ),
                ),

                if (p.richDescription.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _section('Tasting Notes', Icons.wine_bar),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      p.richDescription,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: isDark ? Colors.white70 : Colors.grey[700],
                      ),
                    ),
                  ),
                ],

                if (p.averageRating != null && p.averageRating! > 0) ...[
                  const SizedBox(height: 20),
                  _section('Ratings', Icons.star),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ...List.generate(
                        5,
                        (i) => Icon(
                          i < p.averageRating!.floor()
                              ? Icons.star
                              : Icons.star_half,
                          color: AppColors.memberOffer,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${p.averageRating!.toStringAsFixed(1)} (${p.totalReviewCount} reviews)',
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 32),
                SizedBox(height: MediaQuery.of(context).padding.bottom),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _row(String label, String value, bool isDark) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white54 : Colors.grey[600],
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          ),
        ],
      ),
    );
  }

  static String _countryFlag(String country) {
    final c = country.toLowerCase().trim();
    if (c.contains('australia') || c.contains('aus')) return '🇦🇺';
    if (c.contains('new zealand') || c.contains('nz')) return '🇳🇿';
    if (c.contains('france')) return '🇫🇷';
    if (c.contains('italy')) return '🇮🇹';
    if (c.contains('spain')) return '🇪🇸';
    if (c.contains('argentina')) return '🇦🇷';
    if (c.contains('chile')) return '🇨🇱';
    if (c.contains('usa') ||
        c.contains('united states') ||
        c.contains('california')) {
      return '🇺🇸';
    }
    if (c.contains('germany')) return '🇩🇪';
    if (c.contains('portugal')) return '🇵🇹';
    if (c.contains('south africa')) return '🇿🇦';
    return '';
  }

  Widget _regionRow(Product p, bool isDark) {
    final region = '${p.region}, ${p.state}';
    final country = p.country;
    if (region.trim().isEmpty && country.isEmpty) {
      return const SizedBox.shrink();
    }

    final flag = _countryFlag(country);
    final display = [
      if (flag.isNotEmpty) flag,
      region,
    ].where((s) => s.isNotEmpty).join(' ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Region',
            style: TextStyle(
              color: isDark ? Colors.white54 : Colors.grey[600],
              fontSize: 14,
            ),
          ),
          GestureDetector(
            onTap: () => _openMaps(region, country),
            onLongPress: () => _searchRegion(region, country),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  display,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.open_in_new, size: 13, color: Colors.grey),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openMaps(String region, String country) async {
    final q = Uri.encodeComponent('$region $country wineries');
    await launchUrl(
      Uri.parse('https://www.google.com/maps/search/$q'),
      mode: LaunchMode.externalApplication,
    );
  }

  void _searchRegion(String region, String country) {
    final query = [region, country].where((s) => s.isNotEmpty).join(' ');
    if (query.trim().isEmpty) return;
    Navigator.pop(context, query);
  }
}

// ── Full-screen History with Chart ──
class _ProductHistoryPage extends StatelessWidget {
  final Product product;
  const _ProductHistoryPage({required this.product});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Product History')),
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            TabBar(
              labelColor: isDark ? Colors.white : AppColors.primary,
              unselectedLabelColor: Colors.grey,
              tabs: const [
                Tab(text: 'Price & Stock'),
                Tab(text: 'Product Info'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildPriceStockTab(isDark),
                  _buildProductInfoTab(isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceStockTab(bool isDark) {
    final history = product.priceHistory.toList();
    if (history.isEmpty) {
      return const Center(child: Text('No price history yet'));
    }

    final spots = <FlSpot>[];
    for (var i = 0; i < history.length; i++) {
      spots.add(FlSpot(i.toDouble(), history[i].value));
    }

    final minY = history.map((h) => h.value).reduce((a, b) => a < b ? a : b);
    final maxY = history.map((h) => h.value).reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY) * 0.2;
    final currentPrice = history.last.value;
    final avgPrice =
        history.map((h) => h.value).reduce((a, b) => a + b) / history.length;
    final isHigh = currentPrice > avgPrice;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Price indicator
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isHigh
                  ? Colors.red.withAlpha(20)
                  : Colors.green.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  isHigh ? Icons.trending_up : Icons.trending_down,
                  color: isHigh ? Colors.red : Colors.green,
                ),
                const SizedBox(width: 8),
                Text(
                  isHigh
                      ? 'Above average (avg \$${avgPrice.toStringAsFixed(2)})'
                      : 'Below average (avg \$${avgPrice.toStringAsFixed(2)})',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isHigh ? Colors.red : Colors.green,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Line chart
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minY: minY - padding,
                maxY: maxY + padding,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: isDark ? Colors.white10 : Colors.grey[200]!,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      getTitlesWidget: (v, _) => Text(
                        '\$${v.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white54 : Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= history.length) {
                          return const SizedBox.shrink();
                        }
                        final d = history[i].date;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${d.day}/${d.month}',
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark ? Colors.white54 : Colors.grey[600],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: isDark
                        ? AppColors.memberOffer
                        : AppColors.memberOfferDark,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                        radius: 3,
                        color: AppColors.primary,
                        strokeWidth: 1,
                        strokeColor: Colors.white,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color:
                          (isDark
                                  ? AppColors.memberOffer
                                  : AppColors.memberOfferDark)
                              .withAlpha(30),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => spots
                        .map(
                          (s) => LineTooltipItem(
                            '\$${s.y.toStringAsFixed(2)}',
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Price history list
          Text(
            'Price Records',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          ...history.reversed.map(
            (rec) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    rec.date.toString().substring(0, 16),
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white70 : Colors.grey[600],
                    ),
                  ),
                  Text(
                    '\$${rec.value.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductInfoTab(bool isDark) {
    final hasTitles = product.previousTitles.isNotEmpty;
    if (!hasTitles) {
      return const Center(child: Text('No product info changes recorded'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Previous Names',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Current: ${product.title}',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white70 : Colors.grey[700],
            ),
          ),
          const SizedBox(height: 12),
          ...product.previousTitles.reversed.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.label_outline, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(t, style: const TextStyle(fontSize: 14)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Nearby stores sheet
class _NearbyStoresSheet extends StatefulWidget {
  final String stockcode;
  final String postcode;
  const _NearbyStoresSheet({required this.stockcode, required this.postcode});

  @override
  State<_NearbyStoresSheet> createState() => _NearbyStoresSheetState();
}

class _NearbyStoresSheetState extends State<_NearbyStoresSheet> {
  List<Map<String, dynamic>> _stores = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    final stores = await ApiService.searchStores(widget.postcode);
    if (mounted) {
      setState(() {
        _stores = stores;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (_, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text(
                  'Nearby Stores',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  widget.stockcode,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _stores.isEmpty
                ? const Center(child: Text('No stores found nearby'))
                : ListView.separated(
                    controller: ScrollController()..addListener(() {}),
                    itemCount: _stores.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final s = _stores[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primary.withAlpha(20),
                          child: const Icon(
                            Icons.store,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          (s['Name'] ?? '').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${s['AddressLine1'] ?? ''}, ${s['Suburb'] ?? ''} ${s['State'] ?? ''}',
                        ),
                        trailing: TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            // Switch to this store
                            CacheService.setStoreNo((s['Id'] ?? '').toString());
                            CacheService.setStoreName(
                              (s['Name'] ?? '').toString(),
                            );
                          },
                          child: const Text('Set store'),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// Full-screen image viewer with pinch-to-zoom
class _FullImageViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  const _FullImageViewer({required this.images, required this.initialIndex});

  @override
  State<_FullImageViewer> createState() => _FullImageViewerState();
}

class _FullImageViewerState extends State<_FullImageViewer> {
  late int _index;
  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1}/${widget.images.length}'),
      ),
      body: GestureDetector(
        onTap: () => Navigator.pop(context),
        onHorizontalDragEnd: (d) {
          if (d.primaryVelocity! < -100 && _index < widget.images.length - 1) {
            setState(() => _index++);
          } else if (d.primaryVelocity! > 100 && _index > 0)
            setState(() => _index--);
        },
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Center(
            child: Image.network(
              widget.images[_index],
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.wine_bar, size: 64, color: Colors.grey),
            ),
          ),
        ),
      ),
    );
  }
}

class _PackVariant {
  final String label;
  final double price;
  final String stockcode;
  final String packType;
  final int qty;
  const _PackVariant({
    required this.label,
    required this.price,
    required this.stockcode,
    required this.packType,
    required this.qty,
  });
}
