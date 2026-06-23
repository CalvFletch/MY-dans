import 'package:flutter/material.dart';
import '../main.dart';
import '../models/filters.dart';

class FilterSheet extends StatefulWidget {
  final ProductFilters filters;
  const FilterSheet({super.key, required this.filters});
  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late ProductFilters _f;
  late final _minP, _maxP, _minV, _maxV, _minA, _maxA, _minPpl, _maxPpl;
  late final TextEditingController _countryCtrl, _categoryCtrl;
  bool _andMode = false;

  static const _countries = [
    'Australia',
    'New Zealand',
    'France',
    'Italy',
    'Spain',
    'Argentina',
    'Chile',
    'USA',
    'Germany',
    'Portugal',
    'South Africa',
    'Austria',
    'Greece',
    'Hungary',
    'Japan',
    'Canada',
    'Uruguay',
    'Lebanon',
    'Scotland',
    'Ireland',
    'England',
    'Mexico',
    'China',
    'India',
    'Norway',
    'Sweden',
    'Denmark',
    'Finland',
    'Netherlands',
    'Belgium',
    'Switzerland',
    'Turkey',
    'Georgia',
    'Israel',
    'Morocco',
    'Romania',
    'Bulgaria',
    'Croatia',
    'Slovenia',
    'Brazil',
    'Peru',
    'Thailand',
    'South Korea',
    'Vietnam',
    'Indonesia',
    'Singapore',
    'Malaysia',
    'Taiwan',
    'Czech Republic',
    'Slovakia',
    'Poland',
    'Ukraine',
    'Serbia',
    'Moldova',
    'Luxembourg',
    'Malta',
    'Cyprus',
    'Jamaica', 'Cuba', 'Colombia', 'Ecuador', 'Bolivia', 'Paraguay',
    // AU states & regions
    'South Australia',
    'Victoria',
    'New South Wales',
    'Queensland',
    'Western Australia',
    'Tasmania',
    'Northern Territory', 'Australian Capital Territory',
    // International regions/states
    'California',
    'Oregon',
    'Washington',
    'Texas',
    'New York',
    'Kentucky',
    'Tennessee',
    'Colorado',
    'Bordeaux',
    'Burgundy',
    'Champagne',
    'Loire',
    'Rhône',
    'Provence',
    'Alsace',
    'Languedoc',
    'Tuscany',
    'Piedmont',
    'Veneto',
    'Sicily',
    'Lombardy',
    'Abruzzo',
    'Puglia',
    'Emilia-Romagna',
    'Rioja', 'Catalonia', 'Andalusia', 'Castilla', 'Galicia', 'Basque',
    'Mendoza', 'Salta', 'Patagonia',
    'Barossa Valley',
    'McLaren Vale',
    'Coonawarra',
    'Clare Valley',
    'Eden Valley',
    'Adelaide Hills',
    'Margaret River',
    'Great Southern',
    'Yarra Valley',
    'Mornington Peninsula',
    'Hunter Valley',
    'Marlborough', 'Hawke\'s Bay', 'Central Otago', 'Gisborne',
    'Napa Valley',
    'Sonoma',
    'Willamette Valley',
    'Columbia Valley',
    'Finger Lakes',
    'Stellenbosch', 'Paarl', 'Franschhoek', 'Walker Bay',
    'Mosel', 'Rheingau', 'Pfalz', 'Baden', 'Rheinhessen',
  ];

  static const _regions = {
    'Oceania': ['Australia', 'New Zealand'],
    'Europe': [
      'France',
      'Italy',
      'Spain',
      'Germany',
      'Portugal',
      'Austria',
      'Greece',
      'Hungary',
      'Scotland',
      'Ireland',
      'England',
      'Netherlands',
      'Belgium',
      'Switzerland',
      'Turkey',
      'Georgia',
      'Romania',
      'Bulgaria',
      'Croatia',
      'Slovenia',
      'Norway',
      'Sweden',
      'Denmark',
      'Finland',
      'Czech Republic',
      'Slovakia',
      'Poland',
      'Ukraine',
      'Serbia',
      'Moldova',
      'Luxembourg',
      'Malta',
      'Cyprus',
    ],
    'Scandinavia': ['Norway', 'Sweden', 'Denmark', 'Finland'],
    'Western Europe': [
      'France',
      'Italy',
      'Spain',
      'Germany',
      'Portugal',
      'Austria',
      'Netherlands',
      'Belgium',
      'Switzerland',
      'Ireland',
      'England',
      'Scotland',
    ],
    'Eastern Europe': [
      'Hungary',
      'Romania',
      'Bulgaria',
      'Croatia',
      'Slovenia',
      'Georgia',
      'Turkey',
      'Czech Republic',
      'Slovakia',
      'Poland',
      'Ukraine',
      'Serbia',
      'Moldova',
    ],
    'Americas': [
      'Argentina',
      'Chile',
      'USA',
      'Canada',
      'Uruguay',
      'Mexico',
      'Brazil',
      'Peru',
      'Colombia',
      'Ecuador',
      'Bolivia',
      'Paraguay',
      'Jamaica',
      'Cuba',
    ],
    'Asia': [
      'Japan',
      'China',
      'India',
      'Lebanon',
      'Israel',
      'Thailand',
      'South Korea',
      'Vietnam',
      'Indonesia',
      'Singapore',
      'Malaysia',
      'Taiwan',
    ],
    'Africa': ['South Africa', 'Morocco'],
    // Australian regions
    'AU: Eastern States': [
      'South Australia',
      'Victoria',
      'New South Wales',
      'Queensland',
      'Tasmania',
      'Australian Capital Territory',
    ],
    'AU: Western Australia': ['Western Australia'],
    'AU: All Australia': [
      'South Australia',
      'Victoria',
      'New South Wales',
      'Queensland',
      'Tasmania',
      'Australian Capital Territory',
      'Western Australia',
      'Northern Territory',
    ],
  };

  // Australian state-based region groups (match against webstateoforigin)
  static const _auRegions = {
    'Eastern States': [
      'South Australia',
      'Victoria',
      'New South Wales',
      'Queensland',
      'Tasmania',
      'Australian Capital Territory',
    ],
    'Western Australia': ['Western Australia'],
    'Northern Territory': ['Northern Territory'],
    'All Australia': [
      'South Australia',
      'Victoria',
      'New South Wales',
      'Queensland',
      'Tasmania',
      'Australian Capital Territory',
      'Western Australia',
      'Northern Territory',
    ],
  };

  static const _cats = {
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

  static const _topLevel = [
    'Wine',
    'Beer',
    'Cider',
    'Spirits',
    'RTD',
    'Zero Alcohol Drinks',
    'Accessories',
    'Food Snacks',
    'Gifts',
    'Other Drinks',
  ];

  /// Map country/region name to Unicode flag (regional indicator pair)
  static String _flagFor(String name) {
    const map = {
      'Australia': '🇦🇺',
      'New Zealand': '🇳🇿',
      'France': '🇫🇷',
      'Italy': '🇮🇹',
      'Spain': '🇪🇸',
      'Argentina': '🇦🇷',
      'Chile': '🇨🇱',
      'USA': '🇺🇸',
      'Germany': '🇩🇪',
      'Portugal': '🇵🇹',
      'South Africa': '🇿🇦',
      'Austria': '🇦🇹',
      'Greece': '🇬🇷',
      'Hungary': '🇭🇺',
      'Japan': '🇯🇵',
      'Canada': '🇨🇦',
      'Uruguay': '🇺🇾',
      'Lebanon': '🇱🇧',
      'Scotland': '🏴󠁧󠁢󠁳󠁣󠁴󠁿',
      'Ireland': '🇮🇪',
      'England': '🏴󠁧󠁢󠁥󠁮󠁧󠁿',
      'Mexico': '🇲🇽',
      'China': '🇨🇳',
      'India': '🇮🇳',
      'Norway': '🇳🇴',
      'Sweden': '🇸🇪',
      'Denmark': '🇩🇰',
      'Finland': '🇫🇮',
      'Netherlands': '🇳🇱',
      'Belgium': '🇧🇪',
      'Switzerland': '🇨🇭',
      'Turkey': '🇹🇷',
      'Georgia': '🇬🇪',
      'Israel': '🇮🇱',
      'Morocco': '🇲🇦',
      'Romania': '🇷🇴',
      'Bulgaria': '🇧🇬',
      'Croatia': '🇭🇷',
      'Slovenia': '🇸🇮',
      'Brazil': '🇧🇷',
      'Peru': '🇵🇪',
      'Thailand': '🇹🇭',
      'South Korea': '🇰🇷',
      'Vietnam': '🇻🇳',
      'Indonesia': '🇮🇩',
      'Singapore': '🇸🇬',
      'Malaysia': '🇲🇾',
      'Taiwan': '🇹🇼',
      'Czech Republic': '🇨🇿',
      'Slovakia': '🇸🇰',
      'Poland': '🇵🇱',
      'Ukraine': '🇺🇦',
      'Serbia': '🇷🇸',
      'Moldova': '🇲🇩',
      'Luxembourg': '🇱🇺',
      'Malta': '🇲🇹',
      'Cyprus': '🇨🇾',
      'Jamaica': '🇯🇲',
      'Cuba': '🇨🇺',
      'Colombia': '🇨🇴',
      'Ecuador': '🇪🇨',
      'Bolivia': '🇧🇴',
      'Paraguay': '🇵🇾',
    };
    return map[name] ?? '';
  }

  static const _catIcons = {
    'Wine': Icons.wine_bar,
    'Beer': Icons.sports_bar,
    'Cider': Icons.local_drink,
    'Spirits': Icons.liquor,
    'RTD': Icons.local_cafe,
    'Zero Alcohol Drinks': Icons.no_drinks,
    'Accessories': Icons.wine_bar, // fallback
    'Food Snacks': Icons.restaurant,
    'Gifts': Icons.card_giftcard,
    'Other Drinks': Icons.water_drop,
  };

  @override
  void initState() {
    super.initState();
    _f = ProductFilters()
      ..minPrice = widget.filters.minPrice
      ..maxPrice = widget.filters.maxPrice
      ..minVintage = widget.filters.minVintage
      ..maxVintage = widget.filters.maxVintage
      ..minAlcohol = widget.filters.minAlcohol
      ..maxAlcohol = widget.filters.maxAlcohol
      ..minPricePerLiter = widget.filters.minPricePerLiter
      ..maxPricePerLiter = widget.filters.maxPricePerLiter
      ..countries.addAll(widget.filters.countries)
      ..regions.addAll(widget.filters.regions)
      ..categories.addAll(widget.filters.categories)
      ..inStockOnly = widget.filters.inStockOnly
      ..hideOnline = widget.filters.hideOnline
      ..newOnly = widget.filters.newOnly
      ..categoryAnd = widget.filters.categoryAnd
      ..countryAnd = widget.filters.countryAnd;
    _minP = _c(_f.minPrice);
    _maxP = _c(_f.maxPrice);
    _minV = _ci(_f.minVintage);
    _maxV = _ci(_f.maxVintage);
    _minA = _c(_f.minAlcohol);
    _maxA = _c(_f.maxAlcohol);
    _minPpl = _c(_f.minPricePerLiter);
    _maxPpl = _c(_f.maxPricePerLiter);
    _countryCtrl = TextEditingController();
    _categoryCtrl = TextEditingController();
  }

  TextEditingController _c(double? v) =>
      TextEditingController(text: v?.toInt().toString() ?? '');
  TextEditingController _ci(int? v) =>
      TextEditingController(text: v?.toString() ?? '');

  @override
  void dispose() {
    _minP.dispose();
    _maxP.dispose();
    _minV.dispose();
    _maxV.dispose();
    _minA.dispose();
    _maxA.dispose();
    _minPpl.dispose();
    _maxPpl.dispose();
    _countryCtrl.dispose();
    _categoryCtrl.dispose();
    super.dispose();
  }

  void _sync() {
    _f.minPrice = _p(_minP);
    _f.maxPrice = _p(_maxP);
    _f.minVintage = _pi(_minV, 1900, 2030);
    _f.maxVintage = _pi(_maxV, 1900, 2030);
    _f.minAlcohol = _pc(_minA, 100);
    _f.maxAlcohol = _pc(_maxA, 100);
    _f.minPricePerLiter = _p(_minPpl);
    _f.maxPricePerLiter = _p(_maxPpl);
  }

  double? _p(TextEditingController c) {
    final v = double.tryParse(c.text);
    return v != null && v >= 0 ? v : null;
  }

  double? _pc(TextEditingController c, double m) {
    final v = _p(c);
    return v != null ? (v > m ? m : v) : null;
  }

  int? _pi(TextEditingController c, int min, int max) {
    final v = int.tryParse(c.text);
    return v != null ? v.clamp(min, max) : null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Filters'),
        actions: [
          TextButton(
            onPressed: () {
              _f.clear();
              _minP.clear();
              _maxP.clear();
              _minV.clear();
              _maxV.clear();
              _minA.clear();
              _maxA.clear();
              _minPpl.clear();
              _maxPpl.clear();
              _countryCtrl.clear();
              _categoryCtrl.clear();
              setState(() {});
            },
            child: const Text('Clear', style: TextStyle(color: Colors.white70)),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: () {
              _sync();
              _f.categoryAnd = _andMode;
              _f.countryAnd = _f.countryAnd;
              Navigator.pop(context, _f);
            },
            child: const Text('Apply'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.highlight,
              foregroundColor: Colors.black,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('Price Range'),
          Row(
            children: [
              _field('Min \$', _minP, '0'),
              const SizedBox(width: 12),
              _field('Max \$', _maxP, '∞'),
            ],
          ),
          _h(),
          _section('Vintage'),
          Row(
            children: [
              _field('From', _minV, '1900'),
              const SizedBox(width: 12),
              _field('To', _maxV, '2030'),
            ],
          ),
          _h(),
          _section('Alcohol % (max 100)'),
          Row(
            children: [
              _field('Min %', _minA, '0'),
              const SizedBox(width: 12),
              _field('Max %', _maxA, '100'),
            ],
          ),
          _h(),
          _section('Price per Litre'),
          Row(
            children: [
              _field('Min \$/L', _minPpl, '0'),
              const SizedBox(width: 12),
              _field('Max \$/L', _maxPpl, '∞'),
            ],
          ),
          _h(),
          Row(
            children: [
              _section('Country/Region'),
              const Spacer(),
              if (_f.countries.isNotEmpty || _f.regions.isNotEmpty)
                FilterChip(
                  selected: false,
                  showCheckmark: false,
                  avatar: const Icon(
                    Icons.delete_sweep,
                    size: 16,
                    color: Colors.redAccent,
                  ),
                  label: const SizedBox.shrink(),
                  onSelected: (_) => setState(() {
                    _f.countries.clear();
                    _f.regions.clear();
                  }),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Colors.redAccent.withOpacity(0.08),
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
              const SizedBox(width: 4),
              FilterChip(
                label: Text(
                  _f.countryAnd ? 'AND' : 'OR',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                selected: _f.countryAnd,
                onSelected: (v) => setState(() => _f.countryAnd = v),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          TextField(
            controller: _countryCtrl,
            decoration: InputDecoration(
              hintText: 'Search country, region, state...',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              suffixIcon: _countryCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _countryCtrl.clear();
                        setState(() {});
                      },
                    )
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_countryCtrl.text.length >= 2)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  // Region groups (country + AU region groups)
                  ..._regions.entries
                      .where(
                        (e) => e.key.toLowerCase().contains(
                          _countryCtrl.text.toLowerCase(),
                        ),
                      )
                      .map(
                        (e) => FilterChip(
                          label: Text(
                            e.key,
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: e.value.every(
                            (c) =>
                                _f.countries.contains(c) ||
                                _f.regions.contains(c),
                          ),
                          onSelected: (v) => setState(() {
                            if (v) {
                              _f.countries.addAll(e.value);
                              _f.regions.addAll(e.value);
                            } else {
                              _f.countries.removeAll(e.value);
                              _f.regions.removeAll(e.value);
                            }
                          }),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          backgroundColor:
                              e.value.every(
                                (c) =>
                                    _f.countries.contains(c) ||
                                    _f.regions.contains(c),
                              )
                              ? Theme.of(
                                  context,
                                ).colorScheme.primary.withOpacity(0.12)
                              : null,
                        ),
                      ),
                  // Individual countries/regions/states
                  ..._countries
                      .where(
                        (c) => c.toLowerCase().contains(
                          _countryCtrl.text.toLowerCase(),
                        ),
                      )
                      .map(
                        (c) => FilterChip(
                          label: Text(
                            '${_flagFor(c)} $c',
                            style: const TextStyle(fontSize: 13),
                          ),
                          selected:
                              _f.countries.contains(c) ||
                              _f.regions.contains(c),
                          onSelected: (v) => setState(() {
                            if (v) {
                              _f.countries.add(c);
                              _f.regions.add(c);
                            } else {
                              _f.countries.remove(c);
                              _f.regions.remove(c);
                            }
                          }),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                ],
              ),
            ),
          if (_f.countries.isNotEmpty || _f.regions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 4,
                children: [
                  ..._f.countries.map(
                    (c) => Chip(
                      label: Text(
                        '${_flagFor(c)} $c',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onDeleted: () => setState(() {
                        _f.countries.remove(c);
                      }),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  ..._f.regions
                      .where((r) => !_f.countries.contains(r))
                      .map(
                        (r) => Chip(
                          label: Text(
                            '${_flagFor(r)} $r',
                            style: const TextStyle(fontSize: 12),
                          ),
                          onDeleted: () => setState(() {
                            _f.regions.remove(r);
                          }),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                ],
              ),
            ),
          _h(),
          Row(
            children: [
              _section('Category'),
              const Spacer(),
              if (_f.categories.isNotEmpty)
                FilterChip(
                  selected: false,
                  showCheckmark: false,
                  avatar: const Icon(
                    Icons.delete_sweep,
                    size: 16,
                    color: Colors.redAccent,
                  ),
                  label: const SizedBox.shrink(),
                  onSelected: (_) => setState(() {
                    _f.categories.clear();
                  }),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Colors.redAccent.withOpacity(0.08),
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
              const SizedBox(width: 4),
              FilterChip(
                label: Text(
                  _andMode ? 'AND' : 'OR',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                selected: _andMode,
                onSelected: (v) => setState(() => _andMode = v),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          TextField(
            controller: _categoryCtrl,
            decoration: InputDecoration(
              hintText: 'Search categories...',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              suffixIcon: _categoryCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _categoryCtrl.clear();
                        setState(() {});
                      },
                    )
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          ..._buildNestedCategories(),
          _h(),
          SwitchListTile(
            title: const Text('In stock only'),
            value: _f.inStockOnly,
            onChanged: (v) => setState(() => _f.inStockOnly = v),
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
          SwitchListTile(
            title: const Text('Hide online-only'),
            value: _f.hideOnline,
            onChanged: (v) => setState(() => _f.hideOnline = v),
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
          SwitchListTile(
            title: const Text('New products only'),
            subtitle: const Text('Added in last 90 days'),
            value: _f.newOnly,
            onChanged: (v) => setState(() => _f.newOnly = v),
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 80),
        ],
      ),
    );
  }

  Widget _h() => const SizedBox(height: 16);
  Widget _section(String t) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 6),
    child: Text(
      t,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
  );
  Widget _field(String l, TextEditingController c, String h) => Expanded(
    child: TextField(
      controller: c,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: l,
        hintText: h,
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
      onSubmitted: (_) => _sync(),
      onTapOutside: (_) => _sync(),
    ),
  );

  List<Widget> _buildNestedCategories() {
    final q = _categoryCtrl.text.toLowerCase();
    final widgets = <Widget>[];

    for (final top in _topLevel) {
      final subs = _cats[top] ?? [];
      // Filter by search
      final matchesSearch =
          q.isEmpty ||
          top.toLowerCase().contains(q) ||
          subs.any((s) => s.toLowerCase().contains(q));
      if (!matchesSearch) continue;

      final sel = _f.categories.contains(top);
      final anySubSelected = subs.any((s) => _f.categories.contains(s));
      final expanded = sel || anySubSelected || (q.isNotEmpty && q.length >= 2);

      widgets.add(
        Align(
          alignment: Alignment.centerLeft,
          child: FilterChip(
            avatar: Icon(
              _catIcons[top] ?? Icons.category,
              size: 18,
              color: sel ? AppColors.highlight : Colors.white54,
            ),
            label: Text(
              top,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: sel ? AppColors.highlight : null,
              ),
            ),
            selected: false,
            showCheckmark: false,
            backgroundColor: sel ? AppColors.highlight.withOpacity(0.2) : null,
            side: sel ? const BorderSide(color: AppColors.highlight) : null,
            onSelected: (_) {
              setState(() {
                if (sel) {
                  _f.categories.remove(top);
                  for (final s in subs) {
                    _f.categories.remove(s);
                  }
                  for (final s in subs) {
                    for (final g in (_cats[s] ?? <String>[])) {
                      _f.categories.remove(g);
                    }
                  }
                } else {
                  _f.categories.add(top);
                }
              });
            },
            visualDensity: VisualDensity.compact,
          ),
        ),
      );

      if (expanded) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Wrap(
              spacing: 4,
              runSpacing: 2,
              children: subs
                  .where(
                    (s) =>
                        q.isEmpty ||
                        s.toLowerCase().contains(q) ||
                        top.toLowerCase().contains(q) ||
                        _grandchildMatches(q, s),
                  )
                  .map((s) => _buildSubCategory(top, s, q))
                  .toList(),
            ),
          ),
        );
      }
      widgets.add(const SizedBox(height: 6));
    }
    return widgets;
  }

  Widget _buildSubCategory(String parent, String name, String q) {
    final sel = _f.categories.contains(name);
    final grandkids = _cats[name];
    final hasGrandkids = grandkids != null && grandkids.isNotEmpty;
    final searching = q.length >= 2;
    final showGrandkids =
        hasGrandkids &&
        (sel ||
            (searching && grandkids.any((g) => g.toLowerCase().contains(q))));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilterChip(
          label: Text(
            name,
            style: TextStyle(
              fontSize: 12,
              color: sel ? Colors.cyanAccent : null,
            ),
          ),
          selected: false,
          showCheckmark: false,
          backgroundColor: sel ? Colors.cyanAccent.withOpacity(0.2) : null,
          side: sel ? const BorderSide(color: Colors.cyanAccent) : null,
          onSelected: (_) => setState(() {
            if (sel) {
              _f.categories.remove(name);
              if (hasGrandkids) {
                for (final g in grandkids) {
                  _f.categories.remove(g);
                }
              }
            } else {
              _f.categories.add(name);
              _f.categories.add(parent); // auto-add parent
            }
          }),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        if (showGrandkids)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Wrap(
              spacing: 4,
              runSpacing: 2,
              children: grandkids
                  .where((g) => !searching || g.toLowerCase().contains(q))
                  .map(
                    (g) => FilterChip(
                      label: Text(
                        g,
                        style: TextStyle(
                          fontSize: 11,
                          color: _f.categories.contains(g)
                              ? AppColors.memberOffer
                              : null,
                        ),
                      ),
                      selected: false,
                      showCheckmark: false,
                      backgroundColor: _f.categories.contains(g)
                          ? AppColors.memberOffer.withOpacity(0.25)
                          : null,
                      side: _f.categories.contains(g)
                          ? const BorderSide(color: AppColors.memberOffer)
                          : null,
                      onSelected: (_) => setState(() {
                        if (_f.categories.contains(g)) {
                          _f.categories.remove(g);
                        } else {
                          _f.categories.add(g);
                          _f.categories.add(name);
                          _f.categories.add(parent);
                        }
                      }),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }

  bool _grandchildMatches(String q, String cat) {
    if (q.length < 2) return false;
    final grandkids = _cats[cat];
    if (grandkids == null) return false;
    return grandkids.any((g) => g.toLowerCase().contains(q));
  }
}
