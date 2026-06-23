import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../application/checkout_provider.dart';
import '../../data/biteship_service.dart';

// ─────────────────────────────────────────────────────────────────
// Widget 1: BiteshipAreaSearchField
// Field pencarian area tujuan Biteship dengan autocomplete.
// Ketika user memilih area, memanggil onAreaSelected(area).
// CheckoutProvider yang menangani fetch rates — bukan widget ini.
// ─────────────────────────────────────────────────────────────────
class BiteshipAreaSearchField extends StatefulWidget {
  final String label;
  final BiteshipArea? initialArea;
  final void Function(BiteshipArea area) onAreaSelected;

  const BiteshipAreaSearchField({
    super.key,
    this.label = 'Kecamatan / Kota Tujuan',
    this.initialArea,
    required this.onAreaSelected,
  });

  @override
  State<BiteshipAreaSearchField> createState() =>
      _BiteshipAreaSearchFieldState();
}

class _BiteshipAreaSearchFieldState extends State<BiteshipAreaSearchField> {
  final _controller = TextEditingController();
  final _biteshipService = BiteshipService();
  List<BiteshipArea> _suggestions = [];
  BiteshipArea? _selected;
  bool _isSearching = false;

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
      final results = await _biteshipService.searchArea(query);
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
            hintText: 'Ketik nama kecamatan atau kode pos...',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.search),
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
                          setState(() {
                            _selected = null;
                            _suggestions = [];
                            _controller.clear();
                          });
                        },
                      )
                    : null,
          ),
          onChanged: _search,
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!),
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

// ─────────────────────────────────────────────────────────────────
// Widget 2: BiteshipRatesWidget
//
// Membaca rates dari CheckoutProvider via context.watch — TIDAK
// fetch sendiri. Ini penting agar koordinat GPS ikut terkirim.
//
// Error ditampilkan secara VISIBLE dengan tombol Retry —
// tidak silent fail seperti sebelumnya yang menyebabkan Android
// terlihat tidak ada respons.
// ─────────────────────────────────────────────────────────────────
class BiteshipRatesWidget extends StatelessWidget {
  const BiteshipRatesWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CheckoutProvider>();

    // ── Loading state ─────────────────────────────────────────
    if (provider.isLoadingBiteshipRates) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
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

    // ── Error state — VISIBLE dengan tombol Retry ─────────────
    // Sebelumnya error ini tidak ditampilkan → terlihat kosong di Android
    if (provider.biteshipRatesError != null) {
      return _buildError(context, provider);
    }

    // ── Belum ada area dipilih ────────────────────────────────
    if (provider.selectedDestinationArea == null) {
      return _buildPlaceholder(provider);
    }

    // ── Ada area tapi rates kosong ────────────────────────────
    if (provider.biteshipRates.isEmpty) {
      return _buildEmpty(context, provider);
    }

    // ── Ada rates — tampilkan daftar ──────────────────────────
    return _buildRatesList(context, provider);
  }

  // ── Error dengan pesan lengkap dan tombol Retry ─────────────
  Widget _buildError(BuildContext context, CheckoutProvider provider) {
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.red[400], size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gagal mengambil tarif kurir',
                      style: TextStyle(
                        color: Colors.red[800],
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      provider.biteshipRatesError!,
                      style: TextStyle(color: Colors.red[700], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Coba Lagi'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red[700],
                    side: BorderSide(color: Colors.red[300]!),
                  ),
                  onPressed: () => provider.retryFetchBiteshipRates(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Placeholder saat area belum dipilih ──────────────────────
  Widget _buildPlaceholder(CheckoutProvider provider) {
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
              provider.userAddresses.isNotEmpty
                  ? 'Memuat tarif kurir untuk alamat tersimpan...'
                  : 'Ketik kota/kecamatan tujuan untuk melihat tarif kurir.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // ── Kosong tapi tidak error ───────────────────────────────────
  Widget _buildEmpty(BuildContext context, CheckoutProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
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
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Coba Lagi'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orange[700],
              side: BorderSide(color: Colors.orange[300]!),
            ),
            onPressed: () => provider.retryFetchBiteshipRates(),
          ),
        ],
      ),
    );
  }

  // ── Daftar rates ──────────────────────────────────────────────
  Widget _buildRatesList(BuildContext context, CheckoutProvider provider) {
    final currency =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info area tujuan + tombol Refresh
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          margin: const EdgeInsets.only(bottom: 10),
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
                  style: TextStyle(fontSize: 12, color: Colors.green[700]),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => provider.retryFetchBiteshipRates(),
                child: Text('Refresh',
                    style: TextStyle(fontSize: 11, color: Colors.green[700])),
              ),
            ],
          ),
        ),

        // Daftar rate
        ...provider.biteshipRates
            .map((rate) => _buildRateTile(context, rate, provider, currency)),
      ],
    );
  }

  Widget _buildRateTile(
    BuildContext context,
    BiteshipRate rate,
    CheckoutProvider provider,
    NumberFormat currency,
  ) {
    final isSelected =
        provider.selectedBiteshipRate?.courierId == rate.courierId &&
            provider.selectedBiteshipRate?.courierServiceCode ==
                rate.courierServiceCode;

    return GestureDetector(
      onTap: () => provider.selectBiteshipRate(rate),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withOpacity(0.07)
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
            // Radio indicator
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
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),

            // Logo kurir
            _buildCourierLogo(rate),
            const SizedBox(width: 10),

            // Info layanan
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        rate.courierName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildCategoryBadge(rate),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    rate.serviceName,
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
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
                        fontWeight: FontWeight.bold,
                      ),
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
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryBadge(BiteshipRate rate) {
    final colors = {
      'same_day': Colors.purple,
      'next_day': Colors.blue,
      'cargo': Colors.brown,
      'reguler': Colors.teal,
    };
    final color = colors[rate.category] ?? Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        rate.categoryLabel,
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}