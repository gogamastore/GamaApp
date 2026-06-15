import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/biteship_service.dart';

// ─────────────────────────────────────────────
// Widget 1: Autocomplete area/kota Biteship
// Pasang di form alamat checkout, sebelum form isian
// ─────────────────────────────────────────────
class BiteshipAreaSearchField extends StatefulWidget {
  final String label;
  final void Function(BiteshipArea area) onAreaSelected;
  final BiteshipArea? initialArea;

  const BiteshipAreaSearchField({
    super.key,
    this.label = 'Kota / Kecamatan Tujuan',
    required this.onAreaSelected,
    this.initialArea,
  });

  @override
  State<BiteshipAreaSearchField> createState() =>
      _BiteshipAreaSearchFieldState();
}

class _BiteshipAreaSearchFieldState extends State<BiteshipAreaSearchField> {
  final _controller = TextEditingController();
  final _service = BiteshipService();
  List<BiteshipArea> _suggestions = [];
  bool _isSearching = false;
  BiteshipArea? _selected;

  @override
  void initState() {
    super.initState();
    if (widget.initialArea != null) {
      _selected = widget.initialArea;
      _controller.text = widget.initialArea!.displayName;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    setState(() => _isSearching = true);
    try {
      final results = await _service.searchArea(query);
      if (mounted) setState(() => _suggestions = results);
    } catch (_) {
      if (mounted) setState(() => _suggestions = []);
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: 'Ketik min. 3 huruf, contoh: Makassar',
            border: const OutlineInputBorder(),
            suffixIcon: _isSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _selected != null
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          setState(() {
                            _selected = null;
                            _suggestions = [];
                          });
                        },
                      )
                    : const Icon(Icons.search),
          ),
          onChanged: (v) {
            setState(() => _selected = null);
            _search(v);
          },
        ),
        if (_selected != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Row(
              children: [
                const Icon(Icons.check_circle, size: 14, color: Colors.green),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _selected!.displayName,
                    style: TextStyle(fontSize: 12, color: Colors.green[700]),
                  ),
                ),
              ],
            ),
          ),
        if (_suggestions.isNotEmpty && _selected == null)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
              boxShadow: [
                BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: const Offset(0, 2)),
              ],
            ),
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _suggestions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final area = _suggestions[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.location_on,
                      size: 18, color: Colors.grey),
                  title: Text(area.name, style: const TextStyle(fontSize: 14)),
                  subtitle: Text(
                    '${area.adminName} • ${area.postalCode}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () {
                    setState(() {
                      _selected = area;
                      _suggestions = [];
                      _controller.text = area.displayName;
                    });
                    widget.onAreaSelected(area);
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Widget 2: Daftar tarif kurir Biteship
// Dipasang di CheckoutScreen setelah BiteshipAreaSearchField
// ─────────────────────────────────────────────
class BiteshipRatesWidget extends StatefulWidget {
  final String? destinationAreaId;
  final List<ShipmentItem> items;
  final BiteshipRate? selectedRate;
  final void Function(BiteshipRate rate) onRateSelected;

  const BiteshipRatesWidget({
    super.key,
    required this.destinationAreaId,
    required this.items,
    required this.onRateSelected,
    this.selectedRate,
  });

  @override
  State<BiteshipRatesWidget> createState() => _BiteshipRatesWidgetState();
}

class _BiteshipRatesWidgetState extends State<BiteshipRatesWidget> {
  final _service = BiteshipService();
  List<BiteshipRate> _rates = [];
  bool _isLoading = false;
  String? _error;
  String? _lastAreaId;

  // Filter kategori aktif
  String _activeCategory = 'semua';
  static const _categories = [
    'semua',
    'same_day',
    'next_day',
    'reguler',
    'cargo'
  ];

  @override
  void didUpdateWidget(BiteshipRatesWidget old) {
    super.didUpdateWidget(old);
    if (widget.destinationAreaId != old.destinationAreaId &&
        widget.destinationAreaId != null) {
      _fetchRates();
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.destinationAreaId != null) _fetchRates();
  }

  Future<void> _fetchRates() async {
    if (widget.destinationAreaId == null) return;
    if (widget.destinationAreaId == _lastAreaId) return; // sudah di-fetch

    _lastAreaId = widget.destinationAreaId;
    setState(() {
      _isLoading = true;
      _error = null;
      _rates = [];
    });

    try {
      final rates = await _service.getRates(
        destinationAreaId: widget.destinationAreaId!,
        items: widget.items,
      );
      if (mounted) setState(() => _rates = rates);
    } on BiteshipException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<BiteshipRate> get _filteredRates {
    if (_activeCategory == 'semua') return _rates;
    return _rates.where((r) => r.category == _activeCategory).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.destinationAreaId == null) {
      return _buildPlaceholder();
    }
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Mengambil tarif kurir...',
                  style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      return _buildError();
    }
    if (_rates.isEmpty) {
      return _buildEmpty();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filter kategori
        _buildCategoryFilter(),
        const SizedBox(height: 12),
        // Daftar rate
        ..._filteredRates.map((rate) => _buildRateTile(rate)),
        if (_filteredRates.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Tidak ada layanan untuk kategori ini.',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
        TextButton.icon(
          onPressed: () {
            _lastAreaId = null;
            _fetchRates();
          },
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Refresh Tarif'),
          style: TextButton.styleFrom(foregroundColor: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildCategoryFilter() {
    final labels = {
      'semua': 'Semua',
      'same_day': 'Same Day',
      'next_day': 'Next Day',
      'reguler': 'Reguler',
      'cargo': 'Cargo',
    };
    // Hanya tampilkan kategori yang memang ada datanya
    final available = {'semua', ..._rates.map((r) => r.category)};
    final visible = _categories.where((c) => available.contains(c)).toList();

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: visible.map((cat) {
          final isActive = _activeCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(labels[cat] ?? cat),
              selected: isActive,
              onSelected: (_) => setState(() => _activeCategory = cat),
              selectedColor: Theme.of(context).colorScheme.primary,
              labelStyle: TextStyle(
                color: isActive ? Colors.white : null,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRateTile(BiteshipRate rate) {
    final currency =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final isSelected = widget.selectedRate?.courierId == rate.courierId &&
        widget.selectedRate?.courierServiceCode == rate.courierServiceCode;

    return GestureDetector(
      onTap: () => widget.onRateSelected(rate),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.07)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey[200]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Radio
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey[400]!,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),

            // Logo & nama kurir
            _buildCourierLogo(rate),
            const SizedBox(width: 10),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${rate.courierName} ${rate.serviceName}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildCategoryBadge(rate.category),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 12, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        rate.estimatedDelivery,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Harga
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (rate.hasDiscount)
                  Text(
                    currency.format(rate.originalPrice),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[500],
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                Text(
                  currency.format(rate.price),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                if (rate.hasDiscount)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'DISKON',
                      style: TextStyle(
                          fontSize: 9,
                          color: Colors.red[700],
                          fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCourierLogo(BiteshipRate rate) {
    if (rate.logo != null && rate.logo!.isNotEmpty) {
      return SizedBox(
        width: 36,
        height: 36,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.network(
            rate.logo!,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                _buildCourierInitial(rate.courierName),
          ),
        ),
      );
    }
    return _buildCourierInitial(rate.courierName);
  }

  Widget _buildCourierInitial(String name) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Text(
          name.length >= 2
              ? name.substring(0, 2).toUpperCase()
              : name.toUpperCase(),
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
        ),
      ),
    );
  }

  Widget _buildCategoryBadge(String category) {
    final colors = {
      'same_day': Colors.purple,
      'next_day': Colors.blue,
      'cargo': Colors.brown,
      'reguler': Colors.teal,
    };
    final color = colors[category] ?? Colors.grey;
    final label = const BiteshipRate(
      courierId: '',
      courierName: '',
      courierServiceCode: '',
      serviceName: '',
      description: '',
      price: 0,
      originalPrice: 0,
      discount: 0,
      minDay: 0,
      maxDay: 0,
      estimatedDelivery: '',
      available: true,
      category: '',
    ).categoryLabel;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9, color: color, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.local_shipping_outlined, color: Colors.grey[400]),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Pilih kota/kecamatan tujuan terlebih dahulu untuk melihat tarif kurir.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.red[400], size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_error!,
                    style: TextStyle(color: Colors.red[700], fontSize: 13)),
              ),
            ],
          ),
          TextButton(
            onPressed: () {
              _lastAreaId = null;
              _fetchRates();
            },
            child: const Text('Coba Lagi'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.orange[700]),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Tidak ada layanan kurir tersedia untuk rute ini.',
              style: TextStyle(color: Colors.orange[800], fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
