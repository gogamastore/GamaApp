import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../authentication/data/auth_service.dart';
import '../../orders/domain/order.dart';
import '../data/order_notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _service = OrderNotificationService();
  String? _uid;

  @override
  void initState() {
    super.initState();
    _uid = context.read<AuthService>().currentUser?.uid;
    // Tandai semua notifikasi sudah dilihat saat tab dibuka → badge reset.
    if (_uid != null) {
      _service.markSeen(_uid!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifikasi'),
        centerTitle: true,
      ),
      body: _uid == null
          ? const Center(child: Text('Silakan login untuk melihat notifikasi.'))
          : StreamBuilder<List<Order>>(
              stream: _service.ordersStream(_uid!),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Gagal memuat notifikasi: ${snapshot.error}',
                          textAlign: TextAlign.center),
                    ),
                  );
                }
                final orders = snapshot.data ?? [];
                if (orders.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.notifications_none,
                            size: 64, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('Belum ada notifikasi pesanan',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        SizedBox(height: 4),
                        Text('Informasi status pesanan akan muncul di sini.',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _NotificationCard(order: orders[i]),
                );
              },
            ),
    );
  }
}

class _StatusInfo {
  final String label;
  final String message;
  final IconData icon;
  final Color color;
  const _StatusInfo(this.label, this.message, this.icon, this.color);
}

_StatusInfo _statusInfo(Order o) {
  final status = o.status.toLowerCase();
  final pay = o.paymentStatus.toLowerCase();

  final isCancelled = status.contains('cancel') ||
      status.contains('dibatalkan') ||
      pay == 'cancelled' ||
      pay == 'failed';
  if (isCancelled) {
    return const _StatusInfo(
        'Dibatalkan', 'Pesanan dibatalkan', Icons.cancel, Colors.red);
  }
  if (o.isPendingPayment || pay == 'unpaid' || status == 'pending') {
    return const _StatusInfo('Belum Bayar', 'Menunggu pembayaran',
        Icons.hourglass_bottom, Colors.orange);
  }
  if (status.contains('delivered') || status.contains('selesai')) {
    return const _StatusInfo('Selesai', 'Pesanan telah selesai',
        Icons.check_circle, Colors.green);
  }
  if (status.contains('shipped') || status.contains('dikirim')) {
    return const _StatusInfo('Dikirim', 'Pesanan sedang dikirim',
        Icons.local_shipping, Colors.blue);
  }
  if (status.contains('processing') || o.isPaid) {
    return const _StatusInfo('Diproses',
        'Pembayaran diterima, pesanan diproses', Icons.inventory_2, Colors.teal);
  }
  return _StatusInfo(o.status, 'Status pesanan diperbarui', Icons.info_outline,
      Colors.grey.shade600);
}

class _NotificationCard extends StatelessWidget {
  final Order order;
  const _NotificationCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final info = _statusInfo(order);
    final firstProduct =
        order.products.isNotEmpty ? order.products.first.name : 'Produk';
    final more = order.products.length > 1
        ? ' +${order.products.length - 1} lainnya'
        : '';

    return InkWell(
      onTap: () => context.push('/order-detail', extra: order),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: info.color.withValues(alpha: 0.12),
              child: Icon(info.icon, color: info.color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(info.label,
                          style: TextStyle(
                              fontWeight: FontWeight.bold, color: info.color)),
                      const SizedBox(width: 6),
                      Text('· #${order.id.substring(0, 6)}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(info.message,
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade700)),
                  const SizedBox(height: 4),
                  Text('$firstProduct$more',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(order.formattedDate,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500)),
                      Text(order.formattedTotal,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
