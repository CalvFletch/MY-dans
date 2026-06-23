import 'dart:async';
import 'package:flutter/material.dart';
import '../main.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/search_service.dart';
import '../services/background_service.dart';

class SettingsScreen extends StatefulWidget {
  final bool darkMode;
  final ValueChanged<bool> onToggleDarkMode;

  const SettingsScreen({
    super.key,
    required this.darkMode,
    required this.onToggleDarkMode,
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
  int _reviewThreshold = 300;
  DateTime? _lastDailyRun;

  @override
  void initState() {
    super.initState();
    _loadStore();
    _loadDailyInfo();
    _searchController.addListener(_onSearchChanged);
  }

  Future<void> _loadDailyInfo() async {
    final t = await BackgroundUpdater.getReviewThreshold();
    final last = await BackgroundUpdater.getLastRun();
    setState(() {
      _reviewThreshold = t;
      _lastDailyRun = last;
    });
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
    if (mounted)
      setState(() {
        _stores = stores;
        _loading = false;
      });
  }

  Future<void> _selectStore(Map<String, dynamic> store) async {
    final id = (store['Id'] ?? '').toString();
    final name = (store['Name'] ?? '').toString();
    await CacheService.setStoreNo(id);
    await CacheService.setStoreName(name);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader('My Store', Icons.store),
          const SizedBox(height: 8),
          if (_storeId.isNotEmpty)
            Card(
              color: AppColors.primary.withAlpha(15),
              child: ListTile(
                leading: const Icon(Icons.store, color: AppColors.primary),
                title: Text(
                  _storeName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text('Store #$_storeId'),
                trailing: TextButton(
                  onPressed: () => setState(() {
                    _storeName = '';
                    _storeId = '';
                    CacheService.setStoreNo('');
                    CacheService.setStoreName('');
                  }),
                  child: const Text('Change'),
                ),
              ),
            )
          else ...[
            Text(
              'Search by postcode or suburb.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _searchController,
              autofocus: false,
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
          if (_stores.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${_stores.length} store${_stores.length == 1 ? '' : 's'} found',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            const SizedBox(height: 4),
            ..._stores.map(
              (s) => Card(
                child: ListTile(
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
                    '${s['AddressLine1'] ?? ''}, ${s['Suburb'] ?? ''} ${s['State'] ?? ''} • ${s['Distance'] ?? '?'}km',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _selectStore(s),
                ),
              ),
            ),
          ],
          if (_searchController.text.length >= 3 &&
              _stores.isEmpty &&
              !_loading)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'No stores found. Try a different postcode.',
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
            ),
          const SizedBox(height: 28),
          _sectionHeader('Appearance', Icons.palette),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Dark Mode'),
            secondary: Icon(
              widget.darkMode ? Icons.dark_mode : Icons.light_mode,
              color: AppColors.primary,
            ),
            value: widget.darkMode,
            onChanged: widget.onToggleDarkMode,
          ),
          const SizedBox(height: 28),
          _sectionHeader('Daily Update', Icons.update),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Text('Popular item threshold: '),
                    Text('$_reviewThreshold reviews', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                  Slider(
                    value: _reviewThreshold.toDouble(),
                    min: 50, max: 1000, divisions: 19,
                    label: '$_reviewThreshold',
                    onChanged: (v) => setState(() => _reviewThreshold = v.round()),
                    onChangeEnd: (v) => BackgroundUpdater.setReviewThreshold(v.round()),
                  ),
                  Text(
                    'Products with ≥$_reviewThreshold reviews get daily price & stock updates.',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _lastDailyRun != null
                        ? 'Last update: ${_lastDailyRun!.toString().substring(0, 16)}'
                        : 'No update run yet',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          _sectionHeader('About', Icons.info_outline),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "MY Dan's",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Staff helper for Dan Murphy\'s team members.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Local data: ${SearchService.size} products from promotional catalog',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                  Text(
                    'Live search covers full Dan Murphy\'s range (~8000+ products)',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'v1.0.0',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
