import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'dart:typed_data';
import 'dart:developer' as developer;

import '../../authentication/data/auth_service.dart';
import '../data/order_service.dart';
import '../domain/order.dart';
import 'widgets/biteship_tracking_card.dart';

class OrderDetailScreen extends StatefulWidget {
  final Order order;

  const OrderDetailScreen({super.key, required this.order});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late final OrderService _orderService;
  Uint8List? _paymentProofBytes;
  bool _isUploading = false;
  late Order _currentOrder;

  @override
  void initState() {
    super.initState();
    _orderService = OrderService();
    _currentOrder = widget.order;
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _paymentProofBytes = bytes;
      });
      await _uploadProof();
    }
  }

  Future<void> _uploadProof() async {
    if (_paymentProofBytes == null) return;

    setState(() {
      _isUploading = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userId = authService.currentUser?.uid;

      if (userId == null) {
        throw Exception("User not logged in");
      }

      await _orderService.uploadPaymentProof(
        userId: userId,
        orderId: _currentOrder.id,
        imageBytes: _paymentProofBytes!,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bukti pembayaran berhasil diunggah dan sedang menunggu konfirmasi.')),
      );

      final updatedOrder = await _orderService.getOrderById(_currentOrder.id);
      
      setState(() {
        _currentOrder = updatedOrder;
        _paymentProofBytes = null;
      });

    } catch (e, s) {
      if (!mounted) return;
       developer.log('Error uploading proof', name: 'myapp.order_detail', error: e, stackTrace: s);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengunggah: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  Map<String, dynamic> _getStatusInfo(String status) {
    final s = status.toLowerCase();
    if (s == 'pending' || s == 'belum proses') {
      return {
        'title': 'Pesanan Berhasil Dibuat!',
        'subtitle': 'Terima kasih, pesanan Anda akan segera kami proses.',
        'icon': Icons.schedule,
        'color': Colors.orange,
      };
    }
    if (s == 'processing' || s == 'diproses') {
      return {
        'title': 'Pesanan Sedang Diproses',
        'subtitle': 'Pesanan Anda sedang kami siapkan untuk pengiriman.',
        'icon': Icons.sync,
        'color': Colors.blue,
      };
    }
    if (s == 'delivered' || s == 'dikirim') {
      return {
        'title': 'Pesanan Telah Dikirim',
        'subtitle': 'Pesanan Anda dalam perjalanan menuju alamat tujuan.',
        'icon': Icons.local_shipping,
        'color': Colors.lightGreen,
      };
    }
    if (s == 'shipped' || s == 'selesai') {
      return {
        'title': 'Pesanan Telah Tiba',
        'subtitle': 'Terima kasih telah berbelanja di toko kami.',
        'icon': Icons.done_all,
        'color': Colors.green,
      };
    }
     if (s == 'cancelled' || s == 'dibatalkan') {
      return {
        'title': 'Pesanan Dibatalkan',
        'subtitle': 'Pesanan ini telah dibatalkan.',
        'icon': Icons.cancel,
        'color': Colors.red,
      };
    }
    return {
      'title': 'Status Tidak Diketahui',
      'subtitle': 'Terjadi kesalahan pada status pesanan.',
      'icon': Icons.info,
      'color': Colors.grey,
    };
  }

  String _normalizeStatus(String status) {
    final s = status.toLowerCase();
    if (s == 'pending') return 'Belum Proses';
    if (s == 'processing') return 'Diproses';
    if (s == 'delivered') return 'Dikirim';
    if (s == 'shipped') return 'Selesai';
    if (s == 'cancelled') return 'Dibatalkan';
    return status; // Fallback
  }

  String _normalizePaymentStatus(String paymentStatus, bool hasProof) {
    final ps = paymentStatus.toLowerCase();
    if (ps == 'unpaid' && hasProof) return 'Menunggu Konfirmasi';
    if (ps == 'unpaid') return 'Belum Bayar';
    if (ps == 'paid') return 'Lunas';
    return paymentStatus; 
  }

  @override
  Widget build(BuildContext context) {
    bool hasProof = _currentOrder.paymentProofUrl != null && _currentOrder.paymentProofUrl!.isNotEmpty;
    final statusInfo = _getStatusInfo(_currentOrder.status);
    final normalizedStatus = _normalizeStatus(_currentOrder.status);
    final normalizedPaymentStatus = _normalizePaymentStatus(_currentOrder.paymentStatus, hasProof);
    final currencyFormatter = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail Pesanan'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => context.push('/order-history'),
            tooltip: 'Riwayat Pesanan',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSuccessMessageCard(statusInfo),
            const SizedBox(height: 8),
            _buildOrderInfoCard(currencyFormatter, normalizedStatus),
            const SizedBox(height: 8),
            _buildProductListCard(currencyFormatter),
            const SizedBox(height: 8),
            _buildDeliveryInfoCard(),
            const SizedBox(height: 8),
            _buildPaymentSummaryCard(currencyFormatter),
            const SizedBox(height: 8),
            // Tampilkan DeliveryTrackingCard hanya jika order sudah dikirim
            if (_currentOrder.status.toLowerCase() == 'shipped' ||
                _currentOrder.status.toLowerCase() == 'dikirim')
            const SizedBox(height: 8),
            // Tampilkan BiteshipTrackingCard hanya jika order sudah dikirim dan ada waybill
            if ((_currentOrder.status.toLowerCase() == 'shipped' ||
                _currentOrder.status.toLowerCase() == 'dikirim') &&
                _currentOrder.waybillId != null)
              BiteshipTrackingCard(
                orderId: _currentOrder.id,
                waybillId: _currentOrder.waybillId,
                courierName: _currentOrder.biteshipCourierName,
              ),
            const SizedBox(height: 8),
              _buildPaymentProofCard(normalizedPaymentStatus, hasProof),
            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: _buildActionButtons(),
    );
  }

  Widget _buildSuccessMessageCard(Map<String, dynamic> statusInfo) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Icon(statusInfo['icon'], size: 60, color: statusInfo['color']),
            const SizedBox(height: 16),
            Text(statusInfo['title'], style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center,),
            const SizedBox(height: 8),
            Text(statusInfo['subtitle'], textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium,),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderInfoCard(NumberFormat formatter, String normalizedStatus) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Informasi Pesanan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(height: 20),
            _buildInfoRow('Nomor Pesanan', _currentOrder.id),
            _buildInfoRow('Status', normalizedStatus),
            _buildInfoRow('Tanggal Pesanan', _currentOrder.formattedDate),
          ],
        ),
      ),
    );
  }

   Widget _buildProductListCard(NumberFormat formatter) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Produk Dipesan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(height: 20),
            ..._currentOrder.products.map((product) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  children: [
                    CachedNetworkImage(
                      imageUrl: product.image,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                      errorWidget: (context, url, error) => const Icon(Icons.error),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis,),
                          Text('${product.quantity}x ${formatter.format(product.price)}'),
                        ],
                      ),
                    ),
                    Text(formatter.format(product.quantity * product.price), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryInfoCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Informasi Pengiriman', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(height: 20),
            Text(_currentOrder.customerDetails['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(_currentOrder.customerDetails['whatsapp'] ?? ''),
            const SizedBox(height: 4),
            Text(_currentOrder.customerDetails['address'] ?? ''),
            const SizedBox(height: 12),
             Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.local_shipping, color: Colors.blue[800]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_currentOrder.shippingMethod, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[900])),
                        Text(_currentOrder.paymentMethod.replaceAll('_', ' ').toUpperCase(), style: TextStyle(fontSize: 12, color: Colors.blue[800])),
                      ],
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentSummaryCard(NumberFormat formatter) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ringkasan Pembayaran', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(height: 20),
            _buildInfoRow('Subtotal', formatter.format(_currentOrder.subtotal)),
            _buildInfoRow('Pengiriman', formatter.format(_currentOrder.shippingFee)),
            const Divider(height: 20),
            _buildInfoRow(
              'Total Pembayaran',
              formatter.format(_currentOrder.total),
              isTotal: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentProofCard(String normalizedPaymentStatus, bool hasProof) {
    bool isPaid = normalizedPaymentStatus == 'Lunas';
    bool isWaiting = normalizedPaymentStatus == 'Menunggu Konfirmasi';

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bukti Pembayaran', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(height: 20),
            _buildPaymentStatusIndicator(normalizedPaymentStatus),
            const SizedBox(height: 16),
            if (hasProof)
              _buildExistingProofView(isPaid, isWaiting),
            if (!hasProof && !isPaid) 
              _buildUploadSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentStatusIndicator(String status) {
    bool isPaid = status == 'Lunas';
    bool isWaiting = status == 'Menunggu Konfirmasi';
    MaterialColor color = isPaid ? Colors.green : (isWaiting ? Colors.blue : Colors.orange);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(isPaid ? Icons.check_circle : (isWaiting ? Icons.hourglass_top : Icons.schedule), color: color[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Status Pembayaran: $status',
              style: TextStyle(fontWeight: FontWeight.bold, color: color[700]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExistingProofView(bool isPaid, bool isWaiting) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Bukti yang Sudah Diunggah:', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: _currentOrder.paymentProofUrl!,
            height: 200,
            width: double.infinity,
            fit: BoxFit.cover,
            placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
            errorWidget: (context, url, error) => const Icon(Icons.error, size: 40),
          ),
        ),
        const SizedBox(height: 12),
        if (isWaiting)
           _buildInfoContainer(Icons.info, Colors.blue, 'Bukti pembayaran Anda sedang menunggu konfirmasi oleh Admin.')
        else if (isPaid)
           _buildInfoContainer(Icons.check_circle, Colors.green, 'Pembayaran Anda telah dikonfirmasi. Pesanan sedang diproses.'),

      ],
    );
  }

  Widget _buildUploadSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Unggah Bukti Pembayaran', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text('Silakan unggah bukti transfer untuk mempercepat proses verifikasi.', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 12),
        if (_isUploading)
          const Center(child: CircularProgressIndicator())
        else
          OutlinedButton.icon(
            icon: const Icon(Icons.photo_library),
            label: const Text('Pilih Gambar dari Galeri'),
            onPressed: _pickImage,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              textStyle: const TextStyle(fontSize: 16),
            ),
          ),
      ],
    );
  }
  
  Widget _buildInfoContainer(IconData icon, Color color, String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color is MaterialColor ? color[700] : color),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(color: color is MaterialColor ? color[800] : color)))
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.history),
              label: const Text('Riwayat Lain'),
              onPressed: () => context.go('/order-history'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.shopping_bag),
              label: const Text('Belanja Lagi'),
              onPressed: () => context.go('/'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                foregroundColor: Colors.white,
                backgroundColor: Theme.of(context).primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          const SizedBox(width: 16), // Add some spacing
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis, // Prevent overflow by adding ellipsis
              style: TextStyle(
                fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
                fontSize: isTotal ? 18 : 16,
                color: isTotal ? Theme.of(context).primaryColor : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
