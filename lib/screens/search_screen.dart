import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/database_service.dart';
import '../widgets/product_card.dart';
import '../models/filters.dart';
import 'filter_sheet.dart';
import 'product_screen.dart';
import 'barcode_scanner_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  List<Product> _results = [];
  List<Product> _allResults = [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _showTeamPrices = false;
  String? _error;
  Timer? _debounce;
  final _filters = ProductFilters();
  bool _numPad = false;
  int _filterOffset = 0;
  static const _filterPageSize = 30;
  bool _hasMore = true;
  String _sortMode = 'relevance';

  /// Convert UI sort mode to DB sortField / sortDir
  String get _dbSortField {
    switch (_sortMode) {
      case 'price_asc': case 'price_desc': return 'price';
      case 'name_asc': case 'name_desc': return 'title';
      case 'stock_first': return 'stock_on_hand';
      case 'alcohol_asc': case 'alcohol_desc': case 'ppl_asc': case 'ppl_desc':
      default: return 'review_count';
    }
  }
  String get _dbSortDir {
    switch (_sortMode) {
      case 'price_asc': case 'name_asc': case 'alcohol_asc': case 'ppl_asc': return 'ASC';
      default: return 'DESC';
    }
  }
  /// True if sort can be done in SQL (price, title, stock, review_count)
  bool get _sortInSql => !_sortMode.startsWith('ppl') && !_sortMode.startsWith('alcohol');

  static const _categoryHierarchy = {
    'Wine': [
      'Red Wine',
      'White Wine',
      'Rosé',
      'Champagne Sparkling',
      'Fortified Wine',
    ],
    'Red Wine': [
      'Shiraz',
      'Cabernet Sauvignon',
      'Merlot',
      'Pinot Noir',
      'Grenache',
      'Tempranillo',
      'Sangiovese',
      'Nebbiolo',
      'Malbec',
      'Cabernet Merlot',
      'Shiraz Cabernet',
      'Shiraz Viognier',
      'GSM Blends',
      'Red Blends',
      'Gamay',
      'Barbera',
      'Durif',
      'Montepulciano',
      'Sweet Reds',
      'Cask Reds',
      'Rose',
      'Other Red Varietals',
    ],
    'White Wine': [
      'Sauvignon Blanc',
      'Chardonnay',
      'Riesling',
      'Pinot Gris Grigio',
      'Semillon',
      'Chenin Blanc',
      'Viognier',
      'Moscato Sweet White',
      'Marsanne',
      'Verdelho',
      'Semillon Sauvignon Blanc',
      'Albarino',
      'Vermentino',
      'Garganega',
      'Dessert White',
      'White Blends',
      'Cask Whites',
      'Other White Varietals',
    ],
    'Champagne Sparkling': [
      'Champagne',
      'Prosecco',
      'Sparkling White Wine',
      'Sparkling Rose Wine',
      'Sparkling Red Wine',
      'Sparkling Piccolo',
      'Sweet Sparkling Wine',
      'Cava',
    ],
    'Fortified Wine': [
      'Port Tawny',
      'Sherry Apera',
      'Muscat',
      'Vermouth',
      'Other Fortifieds',
    ],
    'Beer': [
      'Australian Beer',
      'Craft Beer',
      'Full Strength Beer',
      'Mid Strength Beer',
      'Light Beer',
      'Low Carb Beer',
      'International Beer',
      'Alcoholic Ginger Beer',
    ],
    'Cider': ['Apple Cider', 'Pear Cider', 'Fruit Flavoured Cider'],
    'Spirits': [
      'Gin',
      'Vodka',
      'Rum',
      'Tequila',
      'Brandy Cognac',
      'Liqueurs',
      'Aperitifs',
      'Bitters',
      'Absinthe',
      'Sake',
      'Soju Shochu',
      'Baijiu',
      'Ouzo',
      'Pisco',
      'Premix Drinks',
      'Miniatures',
      'Other Spirits',
      'Whisky',
    ],
    'Whisky': [
      'Scotch Whisky',
      'American Whiskey',
      'Irish Whiskey',
      'Japanese Whisky',
      'Australian Whisky',
      'Canadian Whisky',
      'English Whisky',
    ],
    'RTD': ['Premix Drinks'],
    'Zero Alcohol Drinks': [
      'Zero Alcohol Beer',
      'Zero Alcohol Spirits',
      'Zero Alcohol Wine',
    ],
    'Accessories': ['Bar Accessories', 'Glassware', 'Books'],
    'Food Snacks': ['Chips', 'Nuts'],
    'Gifts': [
      'Gift Packs',
      'Gift Boxes Bags',
      'Spirit Gift Packs',
      'Ports Sherries',
    ],
    'Other Drinks': ['Soft Drinks', 'Water', 'Juice', 'Cocktail Mix'],
  };

  bool _hasChildCategorySelected(String parent) {
    final children = _categoryHierarchy[parent];
    if (children == null) return false;
    return children.any((c) => _filters.categories.contains(c));
  }

  static const _sortLabels = {
    'relevance': 'Relevance',
    'price_asc': 'Price ↑',
    'price_desc': 'Price ↓',
    'ppl_asc': '\$/L ↑',
    'ppl_desc': '\$/L ↓',
    'name_asc': 'Name ↑',
    'name_desc': 'Name ↓',
    'alcohol_asc': 'ABV ↑',
    'alcohol_desc': 'ABV ↓',
    'stock_first': 'In Stock',
  };
  static const _sortIcons = {
    'price_asc': Icons.arrow_upward,
    'price_desc': Icons.arrow_downward,
    'ppl_asc': Icons.arrow_upward,
    'ppl_desc': Icons.arrow_downward,
    'name_asc': Icons.arrow_upward,
    'name_desc': Icons.arrow_downward,
    'alcohol_asc': Icons.arrow_upward,
    'alcohol_desc': Icons.arrow_downward,
  };

  static const _sortCycle = {
    'price': ['price_asc', 'price_desc'],
    'ppl': ['ppl_asc', 'ppl_desc'],
    'name': ['name_asc', 'name_desc'],
    'abv': ['alcohol_asc', 'alcohol_desc'],
    'stock': ['stock_first'],
  };

  void _cycleSort(String key) {
    setState(() {
      final cycle = _sortCycle[key];
      if (cycle == null) {
        _sortMode = 'relevance';
      } else if (_sortMode == 'relevance' || !cycle.contains(_sortMode)) {
        _sortMode = cycle.first;
      } else {
        final idx = cycle.indexOf(_sortMode);
        if (idx >= cycle.length - 1) {
          _sortMode = 'relevance';
        } else {
          _sortMode = cycle[idx + 1];
        }
      }
      // If filters active & no text, re-query DB with new sort
      if (_controller.text.trim().isEmpty && _filters.isActive) {
        _search();
      } else {
        _applyFiltersAndSort();
      }
    });
  }

  bool _isSortActive(String key) {
    final cycle = _sortCycle[key];
    if (cycle == null) return _sortMode == 'relevance';
    return cycle.contains(_sortMode);
  }

  Widget _sortChip(String label, String key) {
    final active = _isSortActive(key);
    final showLabel = active ? _sortLabels[_sortMode]! : label;
    final icon = active ? _sortIcons[_sortMode] : null;
    final selected = active || _sortMode == 'relevance' && key == 'relevance';

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: ActionChip(
        avatar: icon != null
            ? Icon(icon, size: 14, color: active ? Colors.white : null)
            : null,
        label: Text(
          showLabel,
          style: TextStyle(fontSize: 13, color: active ? Colors.white : null),
        ),
        onPressed: () => _cycleSort(key),
        visualDensity: VisualDensity.compact,
        backgroundColor: active ? Theme.of(context).colorScheme.primary : null,
        side: active
            ? BorderSide(color: Theme.of(context).colorScheme.primary)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }

  List<Product> _applySort(List<Product> products) {
    switch (_sortMode) {
      case 'price_asc':
        products.sort(
          (a, b) =>
              (a.singlePrice?.value ?? 0).compareTo(b.singlePrice?.value ?? 0),
        );
        break;
      case 'price_desc':
        products.sort(
          (a, b) =>
              (b.singlePrice?.value ?? 0).compareTo(a.singlePrice?.value ?? 0),
        );
        break;
      case 'name_asc':
        products.sort((a, b) => a.title.compareTo(b.title));
        break;
      case 'name_desc':
        products.sort((a, b) => b.title.compareTo(a.title));
        break;
      case 'alcohol_asc':
        products.sort(
          (a, b) => (double.tryParse(a.alcoholVolume.replaceAll('%', '')) ?? 0)
              .compareTo(
                double.tryParse(b.alcoholVolume.replaceAll('%', '')) ?? 0,
              ),
        );
        break;
      case 'alcohol_desc':
        products.sort(
          (a, b) => (double.tryParse(b.alcoholVolume.replaceAll('%', '')) ?? 0)
              .compareTo(
                double.tryParse(a.alcoholVolume.replaceAll('%', '')) ?? 0,
              ),
        );
        break;
      case 'stock_first':
        products.sort((a, b) => b.stockOnHand.compareTo(a.stockOnHand));
        break;
      case 'ppl_asc':
        products.sort((a, b) => (_ppl(a) ?? double.infinity).compareTo(_ppl(b) ?? double.infinity));
        break;
      case 'ppl_desc':
        products.sort((a, b) => (_ppl(b) ?? 0).compareTo(_ppl(a) ?? 0));
        break;
    }
    return products;
  }

  double? _ppl(Product p) {
    final price = p.singlePrice?.value;
    if (price == null || price <= 0) return null;
    final litres = _litresFromPackage(p.packageSize);
    if (litres == null || litres <= 0) return null;
    return price / litres;
  }

  double? _litresFromPackage(String pkg) {
    if (pkg.isEmpty) return null;
    final s = pkg.toLowerCase();
    // Match patterns like "750ml", "1.5L", "375ml", "6x330ml", "24x375ml"
    final multi = RegExp(r'(\d+)\s*x\s*(\d+)\s*ml', caseSensitive: false);
    final mm = multi.firstMatch(s);
    if (mm != null) {
      return int.parse(mm.group(1)!) * int.parse(mm.group(2)!) / 1000.0;
    }
    final ml = RegExp(r'(\d+)\s*ml', caseSensitive: false).firstMatch(s);
    if (ml != null) return int.parse(ml.group(1)!) / 1000.0;
    final l = RegExp(r'([\d.]+)\s*l', caseSensitive: false).firstMatch(s);
    if (l != null) return double.parse(l.group(1)!);
    return 0.75; // default
  }

  void _applyFiltersAndSort() {
    _results = _applySort(_filters.apply(_allResults));
  }

  void _loadMoreFilterResults() {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    _filterOffset += _filterPageSize;
    DatabaseService.instance.searchByFilter(
      countries: _filters.countries.toList(),
      categories: _filters.categories.toList(),
      regions: _filters.regions.toList(),
      inStockOnly: _filters.inStockOnly,
      newOnly: _filters.newOnly,
      limit: _filterPageSize,
      offset: _filterOffset,
      sortField: _dbSortField,
      sortDir: _dbSortDir,
    ).then((results) {
      if (!mounted) return;
      setState(() {
        _allResults.addAll(results);
        _results = _sortInSql ? List.from(_allResults) : _applySort(List.from(_allResults));
        _loadingMore = false;
        _hasMore = results.length >= _filterPageSize;
      });
    });
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_bar, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            'Search or apply a filter to browse',
            style: TextStyle(color: Colors.grey[500], fontSize: 16),
          ),
        ],
      ),
    );
  }

  List<String> _stripParentCategories(List<String> cats) {
    final result = <String>[];
    for (final c in cats) {
      final children = _categoryHierarchy[c];
      if (children == null || children.isEmpty) {
        result.add(c);
        continue;
      }
      if (children.any((child) => cats.contains(child))) continue;
      result.add(c);
    }
    return result;
  }

  void _removeFilter(String type) {
    setState(() {
      switch (type) {
        case 'price':
          _filters.minPrice = null;
          _filters.maxPrice = null;
          break;
        case 'vintage':
          _filters.minVintage = null;
          _filters.maxVintage = null;
          break;
        case 'alcohol':
          _filters.minAlcohol = null;
          _filters.maxAlcohol = null;
          break;
        case 'ppl':
          _filters.minPricePerLiter = null;
          _filters.maxPricePerLiter = null;
          break;
        case 'stock':
          _filters.inStockOnly = false;
          break;
        case 'online':
          _filters.hideOnline = false;
          break;
        case 'new':
          _filters.newOnly = false;
          break;
      }
      _applyFiltersAndSort();
    });
  }

  void _removeCategory(String cat) {
    setState(() {
      final toRemove = <String>{cat};
      _collectDescendants(cat, toRemove);
      _filters.categories.removeAll(toRemove);
      _removeOrphanAncestors();
      _applyFiltersAndSort();
    });
  }

  void _collectDescendants(String cat, Set<String> out) {
    for (final child in _categoryHierarchy[cat] ?? <String>[]) {
      out.add(child);
      _collectDescendants(child, out);
    }
  }

  /// Remove ancestors that have no remaining selected descendants
  void _removeOrphanAncestors() {
    bool changed;
    do {
      changed = false;
      final toCheck = Set<String>.from(_filters.categories);
      for (final cat in toCheck) {
        final children = _categoryHierarchy[cat];
        if (children != null && children.isNotEmpty) {
          final hasChildSelected = children.any(
            (c) =>
                _filters.categories.contains(c) ||
                _categoryHierarchy[c]?.any(
                      (g) => _filters.categories.contains(g),
                    ) ==
                    true,
          );
          if (!hasChildSelected) {
            _filters.categories.remove(cat);
            changed = true;
          }
        }
      }
    } while (changed);
  }

  void _removeCountry(String c) {
    setState(() {
      _filters.countries.remove(c);
      _applyFiltersAndSort();
    });
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
    ApiService.initCatalog();
    _loadSettings();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !_loadingMore && _hasMore && _controller.text.trim().isEmpty && _filters.isActive) {
      _loadMoreFilterResults();
    }
  }

  Future<void> _loadSettings() async {
    _showTeamPrices = await CacheService.getTeamDiscount();
    if (mounted) setState(() {});
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    final query = _controller.text.trim();
    if (query.isEmpty) {
      // Don't clear if filters active — _openFilters triggers search
      if (!_filters.isActive) {
        setState(() {
          _results = [];
          _allResults = [];
          _error = null;
          _loading = false;
        });
      }
      return;
    }
    // Text search
    _debounce = Timer(const Duration(milliseconds: 100), () {
      _search();
    });
  }

  void _search({List<String>? overrideCategories}) {
    final query = _controller.text.trim();

    // Filter-only search
    if (query.isEmpty && _filters.isActive) {
      final cats = overrideCategories ?? _filters.categories.toList();
      setState(() {
        _loading = true;
        _filterOffset = 0;
        _hasMore = true;
      });
      DatabaseService.instance.searchByFilter(
        countries: _filters.countries.toList(),
        categories: cats,
        regions: _filters.regions.toList(),
        inStockOnly: _filters.inStockOnly,
        newOnly: _filters.newOnly,
        limit: _filterPageSize,
        offset: 0,
        sortField: _dbSortField,
        sortDir: _dbSortDir,
      ).then((results) {
        if (!mounted) return;
        // For PPL / ABV sorts, do Dart-side sort; otherwise SQL already sorted
        final sorted = _sortInSql ? results : _applySort(results);
        setState(() {
          _allResults = results;
          _results = sorted;
          _loading = false;
          _hasMore = results.length >= _filterPageSize;
        });
      });
      return;
    }

    if (query.isEmpty) {
      setState(() {
        _allResults = [];
        _results = [];
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);

    ApiService.searchWithApi(
      query,
      onUpdated: () async {
        if (!mounted) return;
        // Quietly re-query local DB — no _loading toggle, no web re-fetch
        final updated =
            DatabaseService.instance.isReady && DatabaseService.instance.count > 0
                ? await DatabaseService.instance.search(query)
                : <Product>[];
        if (!mounted) return;
        if (updated.isNotEmpty) {
          setState(() {
            _allResults = updated;
            _applyFiltersAndSort();
            _error = null;
          });
        }
      },
    ).then((results) {
      if (!mounted) return;
      setState(() {
        _allResults = results;
        _applyFiltersAndSort();
        _loading = false;
        _error = results.isEmpty && query.isNotEmpty ? 'No results' : null;
      });
    });
  }

  void _openFilters() async {
    final result = await Navigator.push<ProductFilters>(
      context,
      MaterialPageRoute(builder: (_) => FilterSheet(filters: _filters)),
    );
    if (result != null && mounted) {
      // Copy filters
      _filters.minPrice = result.minPrice;
      _filters.maxPrice = result.maxPrice;
      _filters.minVintage = result.minVintage;
      _filters.maxVintage = result.maxVintage;
      _filters.minAlcohol = result.minAlcohol;
      _filters.maxAlcohol = result.maxAlcohol;
      _filters.minPricePerLiter = result.minPricePerLiter;
      _filters.maxPricePerLiter = result.maxPricePerLiter;
      _filters.countries.clear();
      _filters.countries.addAll(result.countries);
      _filters.regions.clear();
      _filters.regions.addAll(result.regions);
      _filters.categories.clear();
      _filters.categories.addAll(result.categories);
      _filters.inStockOnly = result.inStockOnly;
      _filters.hideOnline = result.hideOnline;
      _filters.newOnly = result.newOnly;
      _filters.categoryAnd = result.categoryAnd;
      _filters.countryAnd = result.countryAnd;

      // Strip parent categories (e.g. if "Shiraz" selected, remove "Wine"/"Red Wine")
      final cleanCategories = _stripParentCategories(result.categories.toList());

      if (_controller.text.trim().isEmpty) {
        _search(overrideCategories: cleanCategories);
      } else if (_allResults.isEmpty && _filters.isActive) {
        _search();
      } else {
        setState(() => _applyFiltersAndSort());
      }
    }
  }

  int get _filterCount =>
      _filters.countries.length +
      _filters.regions.length +
      _filters.categories.where((c) => !_hasChildCategorySelected(c)).length +
      (_filters.minPrice != null || _filters.maxPrice != null ? 1 : 0) +
      (_filters.minVintage != null || _filters.maxVintage != null ? 1 : 0) +
      (_filters.minAlcohol != null || _filters.maxAlcohol != null ? 1 : 0) +
      (_filters.minPricePerLiter != null || _filters.maxPricePerLiter != null
          ? 1
          : 0) +
      (_filters.inStockOnly ? 1 : 0) +
      (_filters.hideOnline ? 1 : 0) +
      (_filters.newOnly ? 1 : 0);

  Widget _buildFilterChip() {
    final active = _filters.isActive;
    final fgColor = active ? Theme.of(context).colorScheme.primary : null;
    return ActionChip(
      label: Text(
        active ? 'Filters ($_filterCount)' : 'Filters',
        style: TextStyle(fontSize: 13, color: fgColor),
      ),
      onPressed: () => _openFilters(),
      visualDensity: VisualDensity.compact,
      avatar: Icon(
        active ? Icons.filter_alt : Icons.filter_alt_outlined,
        size: 18,
        color: fgColor,
      ),
      backgroundColor: active
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
          : null,
      side: active
          ? BorderSide(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
            )
          : null,
    );
  }

  List<Widget> _buildFilterPills() {
    final pills = <Widget>[];

    if (_filters.minPrice != null || _filters.maxPrice != null) {
      final label = _filters.minPrice != null && _filters.maxPrice != null
          ? '\$${_filters.minPrice!.toStringAsFixed(0)}-\$${_filters.maxPrice!.toStringAsFixed(0)}'
          : _filters.minPrice != null
          ? '≥ \$${_filters.minPrice!.toStringAsFixed(0)}'
          : '≤ \$${_filters.maxPrice!.toStringAsFixed(0)}';
      pills.add(_pill(label, () => _removeFilter('price')));
    }
    if (_filters.minVintage != null || _filters.maxVintage != null) {
      final label = _filters.minVintage != null && _filters.maxVintage != null
          ? '${_filters.minVintage}-${_filters.maxVintage}'
          : _filters.minVintage != null
          ? '≥ ${_filters.minVintage}'
          : '≤ ${_filters.maxVintage}';
      pills.add(_pill('Vintage: $label', () => _removeFilter('vintage')));
    }
    if (_filters.minAlcohol != null || _filters.maxAlcohol != null) {
      final label = _filters.minAlcohol != null && _filters.maxAlcohol != null
          ? '${_filters.minAlcohol!.toStringAsFixed(1)}-${_filters.maxAlcohol!.toStringAsFixed(1)}%'
          : _filters.minAlcohol != null
          ? '≥ ${_filters.minAlcohol!.toStringAsFixed(1)}%'
          : '≤ ${_filters.maxAlcohol!.toStringAsFixed(1)}%';
      pills.add(_pill('ABV: $label', () => _removeFilter('alcohol')));
    }
    if (_filters.minPricePerLiter != null ||
        _filters.maxPricePerLiter != null) {
      final label =
          _filters.minPricePerLiter != null && _filters.maxPricePerLiter != null
          ? '\$${_filters.minPricePerLiter!.toStringAsFixed(0)}-\$${_filters.maxPricePerLiter!.toStringAsFixed(0)}'
          : _filters.minPricePerLiter != null
          ? '≥ \$${_filters.minPricePerLiter!.toStringAsFixed(0)}/L'
          : '≤ \$${_filters.maxPricePerLiter!.toStringAsFixed(0)}/L';
      pills.add(_pill('Price/L: $label', () => _removeFilter('ppl')));
    }
    for (final c in _filters.categories) {
      // Skip parent categories when a child is selected
      if (_hasChildCategorySelected(c)) continue;
      pills.add(_pill(c, () => _removeCategory(c)));
    }
    for (final c in _filters.countries) {
      pills.add(_pill(c, () => _removeCountry(c)));
    }
    for (final r in _filters.regions) {
      pills.add(
        _pill(r, () {
          setState(() {
            _filters.regions.remove(r);
            _applyFiltersAndSort();
          });
        }),
      );
    }
    for (final t in _filters.tags) {
      pills.add(
        _pill(t, () {
          setState(() {
            _filters.tags.remove(t);
            _applyFiltersAndSort();
          });
        }),
      );
    }
    if (_filters.inStockOnly) {
      pills.add(_pill('In Stock', () => _removeFilter('stock')));
    }
    if (_filters.hideOnline) {
      pills.add(_pill('Hide Online', () => _removeFilter('online')));
    }
    if (_filters.newOnly) {
      pills.add(_pill('New Only', () => _removeFilter('new')));
    }

    return pills;
  }

  Widget _pill(String label, VoidCallback onRemove) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InputChip(
        label: Text(label, style: const TextStyle(fontSize: 13)),
        onPressed: onRemove,
        deleteIcon: const Icon(Icons.close, size: 16),
        onDeleted: onRemove,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  void _openScanner() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (code != null && mounted) {
      // If it looks like a stockcode (not just digits), go directly to product
      if (code.contains('_') || code.contains('-') || code.length > 10) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProductScreen(stockcode: code)),
        );
      } else {
        // Raw barcode — use as search term
        _controller.text = code;
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: code.length),
        );
      }
    }
  }

  void _openProduct(Product product) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ProductScreen(stockcode: product.stockcode),
      ),
    );
    if (result != null && mounted) {
      _controller.text = result;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: result.length),
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _controller.removeListener(_onSearchChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Align(
          alignment: Alignment.centerLeft,
          child: SvgPicture.asset(
            'assets/dans-header-banner-1.svg',
            height: 52,
          ),
        ),
        titleSpacing: 16,
        centerTitle: false,
        actions: [
          IconButton(
            icon: SvgPicture.asset(
              'assets/barcode_scanner.svg',
              width: 24,
              height: 24,
              colorFilter: ColorFilter.mode(
                Theme.of(context).colorScheme.onSurface,
                BlendMode.srcIn,
              ),
            ),
            tooltip: 'Scan barcode',
            onPressed: _openScanner,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              key: ValueKey(_numPad),
              controller: _controller,
              autofocus: true,
              keyboardType: _numPad ? TextInputType.number : TextInputType.text,
              cursorColor: Theme.of(context).colorScheme.onSurface,
              decoration: InputDecoration(
                hintText: 'Search product name or code',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (_controller.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _controller.clear(),
                      ),
                    IconButton(
                      icon: Icon(
                        _numPad ? Icons.keyboard : Icons.dialpad,
                        size: 20,
                      ),
                      tooltip: _numPad
                          ? 'Switch to keyboard'
                          : 'Switch to number pad',
                      onPressed: () => setState(() => _numPad = !_numPad),
                    ),
                  ],
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
              textInputAction: TextInputAction.search,
            ),
          ),

          // Filter button + active pills
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _buildFilterChip(),
                if (_filters.isActive) ...[
                  Container(
                    width: 1,
                    height: 24,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    color: Theme.of(context).dividerColor,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: _buildFilterPills()),
                    ),
                  ),
                ],
                if (!_filters.isActive &&
                    _controller.text.isNotEmpty &&
                    !_loading)
                  Text(
                    '${_results.length} result${_results.length == 1 ? '' : 's'}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
              ],
            ),
          ),

          // Sort by row
          if (_controller.text.isNotEmpty || _filters.isActive)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _sortChip('Relevance', 'relevance'),
                      _sortChip('Price', 'price'),
                      _sortChip('\$/L', 'ppl'),
                      _sortChip('Name', 'name'),
                      _sortChip('ABV', 'abv'),
                      _sortChip('In Stock', 'stock'),
                    ],
                  ),
                ),
              ),
            ),

          const SizedBox(height: 4),

          // Results
          Expanded(
            child: _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 8),
                        Text(_error!, style: TextStyle(color: Colors.grey[600])),
                      ],
                    ),
                  )
                : _loading
                ? const Center(child: CircularProgressIndicator())
                : _controller.text.isEmpty && _results.isEmpty && !_filters.isActive
                ? _buildEmptyState()
                : _results.isEmpty && !_loading
                ? const SizedBox.shrink()
                : ListView.builder(
                    padding: EdgeInsets.only(
                      bottom: 16 + MediaQuery.of(context).padding.bottom,
                    ),
                    itemCount: _results.length,
                    itemBuilder: (_, i) => ProductCard(
                      product: _results[i],
                      onTap: () => _openProduct(_results[i]),
                      showTeamPrice: _showTeamPrices,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
