import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../application/checkout_provider.dart';
import '../../data/biteship_service.dart';

// ─────────────────────────────────────────────
// Widget 1: Autocomplete search area Biteship
// (tidak berubah — tetap fetch sendiri via Cloud Function)
// ─────────────────────────────────────────────
class BiteshipAreaSearchField extends StatefulWidget {
  final String label;
  final void Function(BiteshipArea area) onAreaSelected;
  final BiteshipArea? initialArea;

  const BiteshipAreaSearchField({
    super.key,
    this.label = 'Cari Kota / Kecamatan Tujuan',
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
  void didUpdateWidget(BiteshipAreaSearchField old) {
    super.didUpdateWidget(old);
    // Sinkronkan jika initialArea berubah dari luar (auto-select dari provider)
    if (widget.initialArea?.id != old.initialArea?.id &&
        widget.initialArea != null) {
      _selected = widget.initialArea;
      _controller.text = widget.initialArea!.displayName;
      setState(() => _suggestions = []);
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
              boxShadow: const [
                BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, 2)),
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
                  title: Text(area.name,
                      style: const TextStyle(fontSize: 14)),
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
//
// VERSI BARU: Baca rates dari CheckoutProvider
// (bukan fetch sendiri) agar koordinat GPS ikut terkirim
// dan kurir instan (GoSend/Grab) bisa muncul.
// ─────────────────────────────────────────────
class BiteshipRatesWidget extends StatelessWidget {
  const BiteshipRatesWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CheckoutProvider>();

    // Loading
    if (provider.isLoadingBiteshipRates) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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

    // Error
    if (provider.biteshipRatesError != null) {
      return _buildError(context, provider);
    }

    // Belum ada area dipilih
    if (provider.selectedDestinationArea == null) {
      return _buildPlaceholder();
    }

    // Kosong
    if (provider.biteshipRates.isEmpty) {
      return _buildEmpty(context, provider);
    }

    // Tampilkan rates
    final rates = provider.biteshipRates;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info area tujuan
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.green[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green[200]!),
          ),
          child: Row(
            children: [
              Icon(Icons.location_on, size: 14, color: Colors.green[700]),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Tujuan: ${provider.selectedDestinationArea!.name}',
                  style:
                      TextStyle(fontSize: 12, color: Colors.green[700]),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => provider.fetchBiteshipRates(),
                child: Text('Refresh',
                    style: TextStyle(fontSize: 11, color: Colors.green[700])),
              ),
            ],
          ),
        ),

        // Daftar kurir
        ...rates.map((rate) => _buildRateTile(context, rate, provider)),
      ],
    );
  }

  Widget _buildRateTile(
      BuildContext context, BiteshipRate rate, CheckoutProvider provider) {
    final currency =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final isSelected = provider.selectedBiteshipRate?.courierId == rate.courierId &&
        provider.selectedBiteshipRate?.courierServiceCode == rate.courierServiceCode;

    return GestureDetector(
      onTap: () => provider.selectBiteshipRate(rate),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.07)
              : Colors.white,
          borderRadius: BorderRadius.circular(10),
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
              width: 18,
              height: 18,
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
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),

            // Badge kategori
            _buildCategoryBadge(rate.category),
            const SizedBox(width: 8),

            // Info kurir
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${rate.courierName} ${rate.serviceName}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Row(
                    children: [
                      Icon(Icons.schedule,
                          size: 11, color: Colors.grey[500]),
                      const SizedBox(width: 3),
                      Text(
                        rate.estimatedDelivery,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Harga
            Text(
              currency.format(rate.price),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryBadge(String category) {
    final config = switch (category) {
      'same_day' => ('INSTAN', Colors.green),
      'next_day' => ('NEXT DAY', Colors.blue),
      'cargo'    => ('CARGO', Colors.brown),
      _          => ('REGULER', Colors.teal),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: config.$2.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: config.$2.withValues(alpha: 0.4)),
      ),
      child: Text(
        config.$1,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: config.$2,
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.local_shipping_outlined, color: Colors.grey[400]),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Pilih alamat tersimpan atau ketik kota tujuan untuk melihat tarif kurir.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, CheckoutProvider provider) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.red[400], size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  provider.biteshipRatesError!,
                  style: TextStyle(color: Colors.red[700], fontSize: 13),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: () => provider.fetchBiteshipRates(),
            child: const Text('Coba Lagi'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, CheckoutProvider provider) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.orange[700]),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Tidak ada layanan kurir tersedia untuk rute ini.',
                  style: TextStyle(color: Colors.orange[800], fontSize: 13),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: () => provider.fetchBiteshipRates(),
            child: const Text('Coba Lagi'),
          ),
        ],
      ),
    );
  }
}
