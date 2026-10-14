import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:myapp/src/features/checkout/data/biteship_service.dart';

/// Card tracking pengiriman Biteship (JNE, J&T, SiCepat, dll).
/// Pasang di OrderDetailScreen saat status order = "Dikirim".
///
/// Contoh pemakaian:
///   BiteshipTrackingCard(orderId: order.id)
class BiteshipTrackingCard extends StatefulWidget {
  final String orderId;
  final String? waybillId; // opsional — untuk tampilan awal
  final String? courierName; // opsional — untuk tampilan awal

  const BiteshipTrackingCard({
    super.key,
    required this.orderId,
    this.waybillId,
    this.courierName,
  });

  @override
  State<BiteshipTrackingCard> createState() => _BiteshipTrackingCardState();
}

class _BiteshipTrackingCardState extends State<BiteshipTrackingCard> {
  final _service = BiteshipService();
  BiteshipTrackingInfo? _info;
  bool _isLoading = false;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final info = await _service.trackOrder(widget.orderId);
      if (mounted) setState(() => _info = info);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final info = _info;
    if (info == null || !info.hasDelivery) {
      // Tampilkan card minimal jika ada waybill tapi belum ada data tracking
      if (widget.waybillId?.isNotEmpty == true) {
        return _buildMinimalCard();
      }
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header kurir + status
            _buildHeader(info),
            const Divider(height: 24),

            // No resi
            if ((info.waybillId ?? widget.waybillId)?.isNotEmpty == true)
              _buildWaybillRow(info.waybillId ?? widget.waybillId ?? ''),

            const SizedBox(height: 12),

            // Tombol lacak + refresh
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.track_changes, size: 18),
                    label: const Text('Lacak Paket'),
                    onPressed: () => _openTracking(
                      info.trackingUrl ??
                          'https://biteship.com/tracking/${info.waybillId ?? widget.waybillId ?? ""}',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _load,
                  tooltip: 'Refresh status',
                ),
              ],
            ),

            // History perjalanan paket
            if (info.history.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildHistorySection(info.history),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BiteshipTrackingInfo info) {
    final courierLabel = info.courierName ?? widget.courierName ?? 'Kurir';
    final statusLabel = _statusLabel(info.status);
    final statusColor = _statusColor(info.status);

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.local_shipping, color: Colors.blue[700], size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                courierLabel,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              // Info driver (untuk pengiriman instan: nama + nomor HP).
              if ((info.driverName ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.person, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        info.driverPhone?.isNotEmpty == true
                            ? '${info.driverName} · ${info.driverPhone}'
                            : info.driverName!,
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWaybillRow(String waybill) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.receipt_long, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No. Resi',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                Text(
                  waybill,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      letterSpacing: 0.5),
                ),
              ],
            ),
          ),
          // Tombol salin resi
          TextButton(
            style: TextButton.styleFrom(
                padding: EdgeInsets.zero, minimumSize: const Size(40, 30)),
            onPressed: () {
              // Salin ke clipboard
              // Clipboard.setData(ClipboardData(text: waybill));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Nomor resi disalin'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Salin', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection(List<TrackingHistory> history) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Text(
                  'Riwayat Pengiriman',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.grey,
                ),
              ],
            ),
          ),
        ),
        if (_isExpanded)
          ...history.asMap().entries.map((entry) {
            final i = entry.key;
            final h = entry.value;
            final isFirst = i == 0;
            return _buildHistoryItem(h, isFirst: isFirst);
          }),
      ],
    );
  }

  Widget _buildHistoryItem(TrackingHistory h, {bool isFirst = false}) {
    String formattedTime = h.timestamp;
    try {
      final dt = DateTime.parse(h.timestamp).toLocal();
      formattedTime = DateFormat('d MMM HH:mm', 'id_ID').format(dt);
    } catch (_) {}

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline indicator
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isFirst ? Colors.blue[700] : Colors.grey[400],
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: Colors.grey[300],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _statusLabel(h.status),
                    style: TextStyle(
                      fontWeight: isFirst ? FontWeight.bold : FontWeight.normal,
                      fontSize: 13,
                      color: isFirst ? Colors.blue[700] : Colors.black87,
                    ),
                  ),
                  // Keterangan Bahasa Indonesia; bila kosong pakai catatan asli.
                  Builder(builder: (context) {
                    final desc = _statusDesc(h.status);
                    final text = desc.isNotEmpty ? desc : h.note;
                    if (text.isEmpty) return const SizedBox.shrink();
                    return Text(text,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]));
                  }),
                  Text(formattedTime,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMinimalCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.courierName ?? 'Pengiriman',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (widget.waybillId?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              _buildWaybillRow(widget.waybillId!),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.track_changes),
                label: const Text('Lacak Paket'),
                onPressed: () => _openTracking(
                  'https://biteship.com/tracking/${widget.waybillId ?? ""}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Judul status dalam Bahasa Indonesia — mengikuti istilah halaman tracking
  /// Biteship (mis. "Pesanan Sedang Dalam Perjalanan").
  static bool _has(String s, List<String> keys) => keys.any(s.contains);

  // Kata kunci status Biteship per fase.
  static const _kOnTheWay = ['dropping_off', 'in_transit', 'on_process', 'out_for_delivery', 'on_the_way', 'delivering'];
  static const _kFailed = ['cancelled', 'canceled', 'rejected', 'failed', 'not_found'];

  String _statusLabel(String? status) {
    if (status == null || status.isEmpty) return 'Memproses…';
    final s = status.toLowerCase();
    if (s.contains('confirmed')) return 'Permintaan Pengiriman Telah Diterima';
    if (_has(s, ['allocating', 'waiting'])) return 'Mencari Kurir';
    if (s.contains('allocated')) return 'Permintaan Pengiriman Telah Diterima';
    if (s.contains('picking_up') || s == 'pickup') return 'Pesanan Sedang Proses Penjemputan';
    if (s.contains('picked')) return 'Pesanan Telah Dijemput';
    if (_has(s, _kOnTheWay)) return 'Pesanan Sedang Dalam Perjalanan';
    if (s.contains('delivered')) return 'Pesanan Telah Sampai Tujuan';
    if (s.contains('hold')) return 'Pengiriman Tertunda';
    if (s.contains('return')) return 'Paket Dikembalikan';
    if (_has(s, _kFailed)) return 'Pengiriman Gagal / Dibatalkan';
    return status;
  }

  /// Keterangan status dalam Bahasa Indonesia (dipakai bila Biteship tidak
  /// mengirim catatan).
  String _statusDesc(String? status) {
    final s = status?.toLowerCase() ?? '';
    if (s.contains('confirmed')) return 'Pesanan kurir dikonfirmasi. Kurir telah diberi tahu untuk menjemput.';
    if (_has(s, ['allocating', 'waiting'])) return 'Sedang mencari kurir terdekat.';
    if (s.contains('allocated')) return 'Kurir telah dialokasikan. Menunggu dijemput.';
    if (s.contains('picking_up') || s == 'pickup') return 'Kurir sedang menuju lokasi penjemputan.';
    if (s.contains('picked')) return 'Paket telah dijemput kurir.';
    if (_has(s, _kOnTheWay)) return 'Paket sedang menuju alamat tujuan.';
    if (s.contains('delivered')) return 'Paket telah sampai di tujuan.';
    if (s.contains('hold')) return 'Pengiriman tertunda sementara.';
    if (s.contains('return')) return 'Paket dikembalikan ke pengirim.';
    if (_has(s, _kFailed)) return 'Pengiriman dibatalkan atau gagal.';
    return '';
  }

  Color _statusColor(String? status) {
    final s = status?.toLowerCase() ?? '';
    if (s.contains('delivered')) return Colors.green;
    if (s.contains('return') || _has(s, _kFailed)) return Colors.red;
    if (_has(s, _kOnTheWay)) return Colors.blue;
    return Colors.orange;
  }

  Future<void> _openTracking(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
