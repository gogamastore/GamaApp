import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../checkout/data/biteship_service.dart';
import '../domain/order.dart';

class OrderDetailScreen extends StatefulWidget {
  final Order order;
  const OrderDetailScreen({super.key, required this.order});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late Order _order;
  bool _isLoadingTracking = false;
  BiteshipTrackingInfo? _trackingInfo;
  String? _trackingError;

  final _biteshipService = BiteshipService();
  final _currency =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _listenOrderUpdates();
  }

  void _listenOrderUpdates() {
    FirebaseFirestore.instance
        .collection('orders')
        .doc(_order.id)
        .snapshots()
        .listen((doc) {
      if (!doc.exists || !mounted) return;
      final updated = Order.fromFirestore(doc);
      final wasWaitingPayment = _order.isPendingPayment;
      setState(() => _order = updated);
      if (wasWaitingPayment && updated.paymentStatus == 'failed') {
        _showExpiredDialog();
      }
    });
  }

  void _showExpiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Pembayaran Kadaluarsa'),
        content: const Text(
          'Batas waktu pembayaran telah habis. Pesanan ini telah dibatalkan secara otomatis.',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            child: const Text('OK'),
            onPressed: () {
              Navigator.of(ctx).pop();
              context.pop();
            },
          ),
        ],
      ),
    );
  }


  // ── Buka Midtrans untuk bayar ─────────────────────────────────
  void _openPayment() {
    final url = _order.midtransRedirectUrl;
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL pembayaran tidak tersedia.')),
      );
      return;
    }
    context.push('/payment-webview', extra: {
      'orderId': _order.id,
      'redirectUrl': url,
    });
  }

  // ── Lacak pengiriman Biteship ─────────────────────────────────
  Future<void> _trackDelivery() async {
    setState(() {
      _isLoadingTracking = true;
      _trackingError = null;
    });
    try {
      final info = await _biteshipService.trackOrder(_order.id);
      if (mounted) setState(() => _trackingInfo = info);
    } on BiteshipException catch (e) {
      if (mounted) setState(() => _trackingError = e.message);
    } catch (e) {
      developer.log('trackDelivery error: $e', name: 'OrderDetailScreen');
      if (mounted) {
        setState(() => _trackingError = 'Gagal mengambil data tracking.');
      }
    } finally {
      if (mounted) setState(() => _isLoadingTracking = false);
    }
  }

  // ── Buka URL tracking di browser ─────────────────────────────
  Future<void> _openTrackingUrl() async {
    final url = _order.deliveryTrackingUrl ?? _trackingInfo?.trackingUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── Konfirmasi pesanan diterima ───────────────────────────────
  void _confirmDelivered() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konfirmasi Terima Pesanan'),
        content: const Text('Apakah Anda yakin pesanan ini sudah diterima?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            child: const Text('Batal', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          TextButton(
            child: const Text('Ya, Sudah Diterima'),
            onPressed: () {
              Navigator.of(ctx).pop();
              _updateStatusDelivered();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _updateStatusDelivered() async {
    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(_order.id)
          .update({
        'status': 'delivered',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pesanan ditandai sudah diterima.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memperbarui status: $e')),
      );
    }
  }

  // ── Status info ───────────────────────────────────────────────
  Map<String, dynamic> _statusInfo(String status) {
    final s = status.toLowerCase();
    if (s == 'pending') {
      return {
        'title': 'Menunggu Diproses',
        'icon': Icons.schedule,
        'color': Colors.orange,
      };
    }
    if (s == 'processing') {
      return {
        'title': 'Sedang Diproses',
        'icon': Icons.sync,
        'color': Colors.blue,
      };
    }
    if (s == 'shipped') {
      return {
        'title': 'Dalam Pengiriman',
        'icon': Icons.local_shipping,
        'color': Colors.lightGreen,
      };
    }
    if (s == 'delivered') {
      return {
        'title': 'Pesanan Selesai',
        'icon': Icons.done_all,
        'color': Colors.green,
      };
    }
    if (s == 'cancelled') {
      return {
        'title': 'Pesanan Dibatalkan',
        'icon': Icons.cancel,
        'color': Colors.red,
      };
    }
    return {
      'title': 'Status: $status',
      'icon': Icons.info,
      'color': Colors.grey,
    };
  }

  @override
  Widget build(BuildContext context) {
    final statusInfo = _statusInfo(_order.status);
    final statusColor = statusInfo['color'] as Color;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail Pesanan'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusCard(statusInfo, statusColor),
            const SizedBox(height: 16),
            _buildActionButtons(),
            _buildSection('Informasi Pesanan', [
              _buildInfoRow('ID Pesanan', '#${_order.id}'),
              _buildInfoRow('Tanggal', _order.formattedDate),
              _buildInfoRow('Metode Bayar', _paymentMethodLabel(_order.paymentMethod)),
              _buildInfoRow(
                'Status Bayar',
                _paymentLabel(_order.paymentStatus),
                valueColor: _paymentColor(_order.paymentStatus),
              ),
            ]),
            const SizedBox(height: 12),
            _buildShippingSection(),
            const SizedBox(height: 12),
            if (_order.hasBiteshipDelivery) _buildTrackingSection(),
            if (_order.hasBiteshipDelivery) const SizedBox(height: 12),
            _buildSection('Alamat Pengiriman', [
              _buildInfoRow('Nama', _order.customerDetails['name'] ?? '-'),
              _buildInfoRow('Alamat', _order.customerDetails['address'] ?? '-'),
              _buildInfoRow(
                  'WhatsApp', _order.customerDetails['whatsapp'] ?? '-'),
            ]),
            const SizedBox(height: 12),
            _buildProductsSection(),
            const SizedBox(height: 12),
            _buildTotalSection(),
            if (['shipped', 'dikirim']
                .contains(_order.status.toLowerCase())) ...[
              const SizedBox(height: 16),
              _buildComplaintButton(),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Tombol aksi ───────────────────────────────────────────────
  Widget _buildActionButtons() {
    final buttons = <Widget>[];

    // 1. Bayar — jika paymentStatus == 'pending_payment'
    if (_order.isPendingPayment) {
      buttons.add(SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: const Icon(Icons.payment),
          label: const Text('Bayar Sekarang', style: TextStyle(fontSize: 15)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _openPayment,
        ),
      ));
      buttons.add(const SizedBox(height: 8));
      buttons.add(Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.orange[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: Colors.orange[700]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Selesaikan pembayaran sebelum batas waktu Midtrans (24 jam).',
                style: TextStyle(fontSize: 12, color: Colors.orange[800]),
              ),
            ),
          ],
        ),
      ));
      buttons.add(const SizedBox(height: 12));
    }

    // 2. Lacak — jika pakai Biteship
    if (_order.hasBiteshipDelivery) {
      buttons.add(Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: _isLoadingTracking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.location_searching),
              label:
                  Text(_isLoadingTracking ? 'Memuat...' : 'Lacak Pengiriman'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _isLoadingTracking ? null : _trackDelivery,
            ),
          ),
          if (_order.deliveryTrackingUrl != null ||
              _trackingInfo?.trackingUrl != null) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.open_in_browser, size: 16),
              label: const Text('Buka'),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _openTrackingUrl,
            ),
          ],
        ],
      ));
      buttons.add(const SizedBox(height: 12));
    }

    // 3. Konfirmasi terima — jika status shipped
    if (_order.status.toLowerCase() == 'shipped') {
      buttons.add(SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Konfirmasi Pesanan Diterima'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _confirmDelivered,
        ),
      ));
      buttons.add(const SizedBox(height: 12));
    }

    if (buttons.isEmpty) return const SizedBox.shrink();
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: buttons);
  }

  // ── Status card ───────────────────────────────────────────────
  Widget _buildStatusCard(Map<String, dynamic> info, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(info['icon'] as IconData, color: color, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              info['title'] as String,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Pengiriman ────────────────────────────────────────────────
  Widget _buildShippingSection() {
    return _buildSection('Pengiriman', [
      _buildInfoRow('Metode', _order.shippingMethod),
      _buildInfoRow('Biaya', _currency.format(_order.shippingFee)),
      if (_order.biteshipCourierName != null)
        _buildInfoRow('Kurir', _order.biteshipCourierName!),
      if (_order.biteshipServiceName != null)
        _buildInfoRow('Layanan', _order.biteshipServiceName!),
      if (_order.waybillId != null && _order.waybillId!.isNotEmpty)
        _buildInfoRow('No. Resi', _order.waybillId!),
      if (_order.biteshipStatus != null)
        _buildInfoRow('Status Kurir', _order.biteshipStatus!),
    ]);
  }

  // ── Tracking ──────────────────────────────────────────────────
  Widget _buildTrackingSection() {
    if (_trackingError != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.red[400], size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _trackingError!,
                style: TextStyle(color: Colors.red[700], fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    if (_trackingInfo == null) return const SizedBox.shrink();
    final info = _trackingInfo!;
    if (!info.hasDelivery) return const SizedBox.shrink();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on, size: 18),
                const SizedBox(width: 6),
                const Text('Lacak Paket',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const Spacer(),
                if (info.status != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      info.status!.toUpperCase(),
                      style: TextStyle(
                          color: Colors.blue[700],
                          fontWeight: FontWeight.bold,
                          fontSize: 10),
                    ),
                  ),
              ],
            ),
            if (info.courierName != null) ...[
              const SizedBox(height: 6),
              Text('Kurir: ${info.courierName}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
            if (info.driverName != null && info.driverName!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text('Driver: ${info.driverName} (${info.driverPhone ?? '-'})',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
            if (info.history.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              ...info.history.take(5).map((h) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(h.status,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500)),
                              if (h.note.isNotEmpty)
                                Text(h.note,
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.grey[500])),
                              Text(h.timestamp,
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.grey[400])),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  // ── Produk ────────────────────────────────────────────────────
  Widget _buildProductsSection() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Produk',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 10),
            ..._order.products.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      if (p.image.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            p.image,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 44,
                              height: 44,
                              color: Colors.grey[200],
                              child: const Icon(Icons.image,
                                  size: 20, color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.shopping_bag_outlined,
                              color: Colors.grey),
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w500),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                            Text(
                              '${_currency.format(p.price)} × ${p.quantity}',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _currency.format(p.price * p.quantity),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  // ── Total ─────────────────────────────────────────────────────
  Widget _buildTotalSection() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _buildInfoRow('Subtotal', _currency.format(_order.subtotal)),
            _buildInfoRow('Ongkir', _currency.format(_order.shippingFee)),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text(
                  _currency.format(_order.total),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Tombol Ajukan Komplain (hanya status shipped) ─────────────
  Widget _buildComplaintButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.report_problem_outlined, color: Colors.orange),
        label: const Text(
          'Ajukan Komplain',
          style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: Colors.orange),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: _openComplaintWhatsApp,
      ),
    );
  }

  Future<void> _openComplaintWhatsApp() async {
    final recipientName =
        _order.customerDetails['name'] ?? '';
    final message = Uri.encodeComponent(
      'Nomor Pesanan : ${_order.id}\n'
      'Jenis Komplain : \n'
      'Nama Penerima : $recipientName\n\n'
      'Note: Sertakan video unboxing jika produk kurang atau bermasalah.',
    );
    final uri = Uri.parse('https://wa.me/6282345881931?text=$message');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak dapat membuka WhatsApp.')),
        );
      }
    }
  }

  Widget _buildSection(String title, List<Widget> rows) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 10),
            ...rows,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }

  String _paymentMethodLabel(String pm) {
    switch (pm.toLowerCase()) {
      case 'midtrans':
        return 'Online (Midtrans)';
      case 'cod':
        return 'Bayar di Tempat (COD)';
      case 'bank_transfer':
        return 'Transfer Bank';
      default:
        return pm;
    }
  }

  String _paymentLabel(String ps) {
    switch (ps.toLowerCase()) {
      case 'paid':
      case 'settlement':
        return 'Lunas';
      case 'pending_payment':
        return 'Menunggu Pembayaran';
      case 'cancelled':
        return 'Dibatalkan';
      case 'failed':
        return 'Kadaluarsa';
      case 'unpaid':
        return 'Belum Bayar';
      default:
        return ps;
    }
  }

  Color _paymentColor(String ps) {
    switch (ps.toLowerCase()) {
      case 'paid':
      case 'settlement':
        return Colors.green;
      case 'pending_payment':
        return Colors.orange;
      case 'cancelled':
      case 'failed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
