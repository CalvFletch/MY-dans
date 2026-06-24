import 'package:flutter/material.dart';
import '../main.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';

class StoreSheet extends StatefulWidget {
  final String stockcode;
  final String? postcode;
  final double? refLat;
  final double? refLng;
  final String? refName;

  const StoreSheet({
    super.key,
    required this.stockcode,
    this.postcode,
    this.refLat,
    this.refLng,
    this.refName,
  });

  @override
  State<StoreSheet> createState() => _StoreSheetState();
}

class _StoreSheetState extends State<StoreSheet> {
  List<Map<String, dynamic>> _stores = [];
  bool _loading = true;
  String? _error;
  String _sortBy = 'distance'; // 'distance' | 'stock'

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Use provided postcode or fall back to settings
      final pc = widget.postcode ?? (await CacheService.getPostcode());
      final effectivePc = pc.isNotEmpty ? pc : '2000';

      // Fetch stores AND nearby stock in parallel
      final results = await Future.wait([
        ApiService.searchStores(effectivePc),
        ApiService.getNearbyStock(widget.stockcode, effectivePc),
      ]);
      final stores = results[0];
      final stockList = results[1];

      // Merge stock data into stores (match by postcode + distance)
      for (final s in stores) {
        final sPc = (s['Postcode'] ?? '').toString();
        final sDist = (s['Distance'] ?? '').toString();
        // Find matching stock entry
        final match = stockList.where((st) {
          final stPc = (st['Postcode'] ?? '').toString();
          return stPc == sPc;
        }).toList();
        if (match.isNotEmpty) {
          s['_stock'] =
              match.first['AvailableStock'] as int? ??
              match.first['StockQuantity'] as int? ??
              0;
          s['_isAvailable'] = match.first['IsAvailable'] == true;
          s['_packType'] = (match.first['PackType'] ?? '').toString();
        }
      }

      if (widget.refLat != null && widget.refLng != null) {
        for (final s in stores) {
          final lat = double.tryParse((s['Latitude'] ?? '').toString());
          final lng = double.tryParse((s['Longitude'] ?? '').toString());
          if (lat != null && lng != null) {
            s['_direction'] = ApiService.cardinalDirection(
              widget.refLat!,
              widget.refLng!,
              lat,
              lng,
            );
          } else {
            s['_direction'] = '?';
          }
        }
      }
      setState(() {
        _stores = stores;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String? _stateFromPostcode(String pc) {
    // Australian postcode ranges by state
    final p = int.tryParse(pc) ?? 0;
    if (p >= 200 && p <= 299) return 'ACT';
    if (p >= 1000 && p <= 2599) return 'NSW';
    if (p >= 2600 && p <= 2618) return 'ACT';
    if (p >= 2619 && p <= 2899) return 'NSW';
    if (p >= 2900 && p <= 2920) return 'ACT';
    if (p >= 2921 && p <= 2999) return 'NSW';
    if (p >= 3000 && p <= 3999) return 'VIC';
    if (p >= 4000 && p <= 4999) return 'QLD';
    if (p >= 5000 && p <= 5799) return 'SA';
    if (p >= 5800 && p <= 5999) return 'WA';
    if (p >= 6000 && p <= 6799) return 'WA';
    if (p >= 7000 && p <= 7999) return 'TAS';
    if (p >= 800 && p <= 999) return 'NT';
    return null;
  }

  String _stateFromStore(Map<String, dynamic> store) {
    final pc = int.tryParse((store['Postcode'] ?? '').toString()) ?? 0;
    if (pc >= 200 && pc <= 299) return 'ACT';
    if (pc >= 1000 && pc <= 2599) return 'NSW';
    if (pc >= 2600 && pc <= 2618) return 'ACT';
    if (pc >= 2619 && pc <= 2899) return 'NSW';
    if (pc >= 2900 && pc <= 2920) return 'ACT';
    if (pc >= 2921 && pc <= 2999) return 'NSW';
    if (pc >= 3000 && pc <= 3999) return 'VIC';
    if (pc >= 4000 && pc <= 4999) return 'QLD';
    if (pc >= 5000 && pc <= 5799) return 'SA';
    if (pc >= 5800 && pc <= 5999) return 'WA';
    if (pc >= 6000 && pc <= 6799) return 'WA';
    if (pc >= 7000 && pc <= 7999) return 'TAS';
    if (pc >= 800 && pc <= 999) return 'NT';
    return '?';
  }

  List<Map<String, dynamic>> get _filteredSorted {
    var list = _stores.toList();

    // Sort
    if (_sortBy == 'distance') {
      list.sort((a, b) {
        final da = double.tryParse((a['Distance'] ?? '999').toString()) ?? 999;
        final db = double.tryParse((b['Distance'] ?? '999').toString()) ?? 999;
        return da.compareTo(db);
      });
    } else {
      list.sort((a, b) {
        final sa = (a['_stock'] as int?) ?? 0;
        final sb = (b['_stock'] as int?) ?? 0;
        return sb.compareTo(sa); // highest first
      });
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.refName != null
                            ? 'Stores near ${widget.refName}'
                            : 'Nearby Stores',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppColors.primary,
                        ),
                      ),
                    ),
                    // Sort toggle
                    _buildSortChip('Closest', 'distance'),
                    const SizedBox(width: 6),
                    _buildSortChip('Most Stock', 'stock'),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  '${_filteredSorted.length} stores',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              const Divider(),
              // List
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: _filteredSorted.length,
                        itemBuilder: (context, i) =>
                            _buildStoreRow(_filteredSorted[i], isDark),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSortChip(String label, String value) {
    final active = _sortBy == value;
    return GestureDetector(
      onTap: () => setState(() => _sortBy = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? AppColors.primary : Colors.grey[400]!,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: active ? Colors.white : Colors.grey[600],
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildStoreRow(Map<String, dynamic> store, bool isDark) {
    final name = (store['Address'] ?? store['Name'] ?? 'Unknown').toString();
    final dist = double.tryParse((store['Distance'] ?? '').toString());
    final dir = (store['_direction'] ?? '?').toString();
    final postcode = (store['Postcode'] ?? '').toString();
    final state = _stateFromStore(store);
    final stock = store['_stock'] as int?;

    return ListTile(
      dense: true,
      title: Text(
        name,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${dist != null ? '${dist.toStringAsFixed(1)}km ' : ''}· $postcode $state${dir != '?' ? '  $dir' : ''}',
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
      trailing: Text(
        stock != null && stock > 0 ? '$stock' : '\u2014',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
          color: Colors.grey,
        ),
      ),
    );
  }
}
