import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../main.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/database_service.dart';
import '../services/sync_service.dart';

class SettingsScreen extends StatefulWidget {
  final String themeMode;
  final ValueChanged<String> onThemeModeChanged;

  const SettingsScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _searchController = TextEditingController();
  String _storeId = '';
  String _storeName = '';
  List<Map<String, dynamic>> _stores = [];
  bool _loading = false;
  Timer? _debounce;
  bool _teamDiscount = false;
  Map<String, int> _catCounts = {};
  int _totalProducts = 0;
  int _inStock = 0;
  int _syncHour = 2;
  bool _statsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadStore();
    _loadStats();
    _loadSyncSettings();
    _searchController.addListener(_onSearchChanged);
  }

  Future<void> _loadStats() async {
    if (!DatabaseService.instance.isReady) return;
    final db = DatabaseService.instance.db;
    final r = await db.rawQuery("""
      SELECT product_type, COUNT(*) as c,
             SUM(CASE WHEN stock_on_hand > 0 THEN 1 ELSE 0 END) as st
      FROM products WHERE product_type != ''
      GROUP BY product_type ORDER BY c DESC
    """);
    final counts = <String, int>{};
    var stock = 0;
    var total = 0;
    for (final row in r) {
      counts[row['product_type'] as String] = row['c'] as int;
      stock += row['st'] as int;
      total += row['c'] as int;
    }
    if (mounted) {
      // Raw count from DB (includes products with empty product_type)
      final dbTotal = DatabaseService.instance.count;
      setState(() {
        _catCounts = counts;
        _totalProducts = dbTotal > 0 ? dbTotal : total;
        _inStock = stock;
        _statsLoaded = true;
      });
    }
  }

  Future<void> _loadSyncSettings() async {
    final h = await CacheService.getSyncHour();
    if (mounted) setState(() => _syncHour = h);
  }

  Future<void> _loadStore() async {
    final id = await CacheService.getStoreNo();
    final name = await CacheService.getStoreName();
    setState(() {
      _storeId = id;
      _storeName = name;
    });
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    final q = _searchController.text.trim();
    if (q.isEmpty) {
      setState(() {
        _stores = [];
        _loading = false;
      });
      return;
    }
    if (q.length < 3) return;
    _debounce = Timer(const Duration(milliseconds: 300), _searchStores);
  }

  Future<void> _searchStores() async {
    final q = _searchController.text.trim();
    if (q.isEmpty || q.length < 3) return;
    setState(() => _loading = true);
    final stores = await ApiService.searchStores(q);
    if (mounted) {
      setState(() {
        _stores = stores;
        _loading = false;
      });
    }
  }

  Future<void> _selectStore(Map<String, dynamic> store) async {
    final id = (store['Id'] ?? '').toString();
    final name = (store['Name'] ?? '').toString();
    final pc = (store['Postcode'] ?? '').toString();
    await CacheService.setStoreNo(id);
    await CacheService.setStoreName(name);
    if (pc.isNotEmpty) await CacheService.setPostcode(pc);
    setState(() {
      _storeId = id;
      _storeName = name;
      _stores = [];
      _searchController.clear();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Refresh stats if DB is ready but stats never loaded
    if (!_statsLoaded && DatabaseService.instance.isReady) {
      _loadStats();
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _section('Store', Icons.store),
          const SizedBox(height: 6),
          _storeCard(),
          const SizedBox(height: 20),
          _section('Appearance', Icons.palette),
          const SizedBox(height: 6),
          _appearanceCard(),
          const SizedBox(height: 20),
          _section('Nightly Sync', Icons.cloud_sync),
          const SizedBox(height: 6),
          _syncCard(),
          const SizedBox(height: 20),
          _section('Database', Icons.storage),
          const SizedBox(height: 6),
          _dbCard(isDark),
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
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _card({required List<Widget> children}) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  // ── Store ──────────────────────────────────

  Widget _storeCard() {
    if (_storeId.isNotEmpty) {
      return _card(
        children: [
          Row(
            children: [
              const Icon(Icons.store, color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _storeName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Store #$_storeId',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _storeName = '';
                  _storeId = '';
                  CacheService.setStoreNo('');
                  CacheService.setStoreName('');
                }),
                child: const Text('Change'),
              ),
            ],
          ),
        ],
      );
    }
    return _card(
      children: [
        Text(
          'Search by postcode or suburb',
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'e.g. 2000 or Neutral Bay',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => _searchController.clear(),
                  )
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        if (_stores.isNotEmpty) ...[
          const SizedBox(height: 8),
          ..._stores.map(
            (s) => ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withAlpha(20),
                child: const Icon(
                  Icons.store,
                  color: AppColors.primary,
                  size: 18,
                ),
              ),
              title: Text(
                (s['Name'] ?? '').toString(),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              subtitle: Text(
                '${s['Suburb'] ?? ''} ${s['State'] ?? ''} \u2022 ${s['Distance'] ?? '?'}km',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => _selectStore(s),
              dense: true,
            ),
          ),
        ],
      ],
    );
  }

  // ── Appearance ─────────────────────────────

  Widget _appearanceCard() {
    final themeIcon = widget.themeMode == 'system'
        ? Icons.settings_brightness
        : widget.themeMode == 'dark'
        ? Icons.dark_mode
        : Icons.light_mode;
    return _card(
      children: [
        Row(
          children: [
            Icon(themeIcon, color: AppColors.primary, size: 20),
            const SizedBox(width: 10),
            const Text(
              'Theme',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const Spacer(),
            DropdownButton<String>(
              value: widget.themeMode,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(
                  value: 'system',
                  child: Text('System', style: TextStyle(fontSize: 14)),
                ),
                DropdownMenuItem(
                  value: 'light',
                  child: Text('Light', style: TextStyle(fontSize: 14)),
                ),
                DropdownMenuItem(
                  value: 'dark',
                  child: Text('Dark', style: TextStyle(fontSize: 14)),
                ),
              ],
              onChanged: (v) => widget.onThemeModeChanged(v!),
            ),
          ],
        ),
        const Divider(height: 24),
        SwitchListTile(
          title: const Text('Show Team Prices'),
          secondary: Icon(
            _teamDiscount ? Icons.discount : Icons.discount_outlined,
            color: AppColors.spendAndGet,
          ),
          value: _teamDiscount,
          onChanged: (v) async {
            setState(() => _teamDiscount = v);
            await CacheService.setTeamDiscount(v);
          },
          contentPadding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Future<void> _exportDb() async {
    try {
      final data = await DatabaseService.instance.exportDb();
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/mydans_export.db.lz4');
      await file.writeAsBytes(data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Exported ${(data.length / 1024 / 1024).toStringAsFixed(1)} MB to ${file.path}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  // ── Nightly Sync ───────────────────────────

  Widget _syncCard() {
    final labels = {
      -1: 'Manual only',
      0: '12:00 AM AWST',
      1: '1:00 AM AWST',
      2: '2:00 AM AWST (default)',
      3: '3:00 AM AWST',
      4: '4:00 AM AWST',
      22: '10:00 PM AWST',
      23: '11:00 PM AWST',
    };
    return _card(
      children: [
        const Text(
          'Nightly catalog sync from our API',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.schedule, size: 20, color: AppColors.primary),
            const SizedBox(width: 10),
            const Text('Sync at: ', style: TextStyle(fontSize: 14)),
            DropdownButton<int>(
              value: _syncHour,
              items: labels.entries
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(
                        e.value,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) async {
                if (v != null) {
                  setState(() => _syncHour = v);
                  await CacheService.setSyncHour(v);
                  await SyncService.schedule(hour: v);
                }
              },
              underline: const SizedBox(),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _syncHour == -1
              ? 'Sync only when you tap "Sync Now" below.'
              : 'Downloads latest catalog — ~2.6MB diff or ~64MB full. WiFi only, works in background.',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Spacer(),
            TextButton.icon(
              onPressed: () async {
                try {
                  final ok = await DatabaseService.instance.checkRemoteDb();
                  await _loadStats();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok ? 'Catalog updated!' : 'Already up to date',
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
                  }
                }
              },
              icon: const Icon(Icons.cloud_download, size: 18),
              label: const Text('Sync Now'),
            ),
          ],
        ),
      ],
    );
  }

  // ── Database ───────────────────────────────

  Widget _dbCard(bool isDark) {
    final catIcons = {
      'Wine': Icons.wine_bar,
      'Beer': Icons.sports_bar,
      'Spirit': Icons.local_bar,
      'RTD': Icons.local_drink,
      'Standard': Icons.liquor,
    };
    return _card(
      children: [
        Row(
          children: [
            _statBox('Total', '$_totalProducts', AppColors.primary, isDark),
            const SizedBox(width: 8),
            _statBox('In Stock', '$_inStock', Colors.green, isDark),
            const SizedBox(width: 8),
            _statBox('Reviews', '8003', Colors.orange, isDark),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Categories',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 6),
        ..._catCounts.entries
            .take(5)
            .map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Icon(
                      catIcons[e.key] ?? Icons.category,
                      size: 16,
                      color: isDark ? Colors.white54 : Colors.grey[600],
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 80,
                      child: Text(e.key, style: const TextStyle(fontSize: 13)),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: _totalProducts > 0
                              ? e.value / _totalProducts
                              : 0,
                          minHeight: 14,
                          backgroundColor: isDark
                              ? Colors.white10
                              : Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.primary.withAlpha(180),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 50,
                      child: Text(
                        '${e.value}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              'DB v5 \u2022 LZ4 \u2022 $_totalProducts products',
              style: TextStyle(color: Colors.grey[400], fontSize: 11),
            ),
            const Spacer(),
            IconButton(
              onPressed: _exportDb,
              icon: const Icon(Icons.upload_file, size: 18),
              tooltip: 'Export DB',
              style: IconButton.styleFrom(
                backgroundColor: AppColors.primary.withAlpha(25),
                padding: const EdgeInsets.all(6),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statBox(String label, String value, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withAlpha(isDark ? 25 : 15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white54 : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
