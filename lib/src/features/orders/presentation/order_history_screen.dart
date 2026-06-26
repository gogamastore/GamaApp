import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../authentication/data/auth_service.dart';
import '../domain/order.dart';

// ─────────────────────────────────────────────────────────────────
// Satu Firestore listener → semua order user → filter client-side
//
// Tab filtering:
//   "Belum Bayar"  → paymentStatus == 'pending_payment'
//   "Diproses"     → status == 'processing'
//   "Dikirim"      → status IN ['shipped','dikirim']
//   "Selesai"      → status IN ['delivered','selesai']
//   "Dibatalkan"   → paymentStatus IN ['cancelled','failed']
//                    ATAU status IN ['cancelled','dibatalkan']
//                    (menangkap pembatalan dari Biteship webhook)
//   "Semua"        → tanpa filter
// ─────────────────────────────────────────────────────────────────

class OrderHistoryScreen extends StatefulWidget {
  final String? initialTab;
  const OrderHistoryScreen({super.key, this.initialTab});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Order> _orders = [];
  bool _loading = true;
  StreamSubscription<QuerySnapshot>? _sub;

  static const _tabs = [
    _Tab('Belum Bayar', 'pending_payment'),
    _Tab('Diproses', 'processing'),
    _Tab('Dikirim', 'shipped'),
    _Tab('Selesai', 'delivered'),
    _Tab('Dibatalkan', 'cancelled'),
    _Tab('Semua', 'semua'),
  ];

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('id_ID');
    int initialIndex = 0;
    if (widget.initialTab != null) {
      final idx = _tabs.indexWhere((t) => t.key == widget.initialTab);
      if (idx >= 0) initialIndex = idx;
    }
    _tabController = TabController(
        length: _tabs.length, vsync: this, initialIndex: initialIndex);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub == null) _setupListener();
  }

  void _setupListener() {
    final userId = context.read<AuthService>().currentUser?.uid;
    if (userId == null) {
      setState(() => _loading = false);
      return;
    }

    _sub = FirebaseFirestore.instance
        .collection('orders')
        .where('customerId', isEqualTo: userId)
        .orderBy('date', descending: true)
        .snapshots()
        .listen((snap) {
      if (mounted) {
        setState(() {
          _orders = snap.docs.map((d) => Order.fromFirestore(d)).toList();
          _loading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  List<Order> _filterOrders(String tabKey) {
    switch (tabKey) {
      case 'pending_payment':
        return _orders
            .where((o) => o.paymentStatus.toLowerCase() == 'pending_payment')
            .toList();
      case 'processing':
        return _orders
            .where((o) => o.status.toLowerCase() == 'processing')
            .toList();
      case 'shipped':
        return _orders
            .where((o) => ['shipped', 'dikirim'].contains(o.status.toLowerCase()))
            .toList();
      case 'delivered':
        return _orders
            .where((o) => ['delivered', 'selesai'].contains(o.status.toLowerCase()))
            .toList();
      case 'cancelled':
        return _orders.where((o) {
          final ps = o.paymentStatus.toLowerCase();
          final st = o.status.toLowerCase();
          return ['cancelled', 'failed'].contains(ps) ||
              ['cancelled', 'dibatalkan'].contains(st);
        }).toList();
      default:
        return _orders;
    }
  }

  String _emptyMessage(String tabKey) {
    switch (tabKey) {
      case 'pending_payment':
        return 'Tidak ada pesanan yang menunggu pembayaran.';
      case 'processing':
        return 'Tidak ada pesanan yang sedang diproses.';
      case 'shipped':
        return 'Tidak ada pesanan yang sedang dikirim.';
      case 'delivered':
        return 'Belum ada pesanan yang selesai.';
      case 'cancelled':
        return 'Tidak ada pesanan yang dibatalkan.';
      default:
        return 'Anda belum memiliki riwayat pesanan.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.read<AuthService>().currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Pesanan'),
        elevation: 1,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: _tabs.map((t) {
            final count = _filterOrders(t.key).length;
            return Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.label),
                  if (count > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
          indicatorColor: Theme.of(context).colorScheme.primary,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: Colors.grey[600],
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
      body: userId == null
          ? const Center(child: Text('Silakan login.'))
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: _tabs.map((t) {
                    final filtered = _filterOrders(t.key);
                    return _OrderListView(
                      orders: filtered,
                      emptyMessage: _emptyMessage(t.key),
                    );
                  }).toList(),
                ),
    );
  }
}

class _Tab {
  final String label;
  final String key;
  const _Tab(this.label, this.key);
}

// ─────────────────────────────────────────────────────────────────
// List view per-tab (menerima list yang sudah difilter)
// ─────────────────────────────────────────────────────────────────
class _OrderListView extends StatelessWidget {
  final List<Order> orders;
  final String emptyMessage;
  const _OrderListView({required this.orders, required this.emptyMessage});

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(emptyMessage,
                style: TextStyle(fontSize: 15, color: Colors.grey[500]),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: orders.length,
      itemBuilder: (_, i) => _OrderCard(order: orders[i]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// OrderCard
// ─────────────────────────────────────────────────────────────────
class _OrderCard extends StatelessWidget {
  final Order order;
  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final currency =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/order-detail', extra: order),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '#${order.id.substring(0, order.id.length.clamp(0, 8)).toUpperCase()}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  Text(order.formattedDate,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ],
              ),
              const SizedBox(height: 8),

              // Produk
              ...order.products.take(2).map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text('${p.name} ×${p.quantity}',
                        style: const TextStyle(fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  )),
              if (order.products.length > 2)
                Text('+${order.products.length - 2} produk lainnya',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              const SizedBox(height: 10),

              // Footer
              Row(
                children: [
                  Expanded(
                    child: Text(currency.format(order.total),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                  _buildPaymentBadge(order.paymentStatus),
                  const SizedBox(width: 6),
                  _buildStatusBadge(order.status),
                ],
              ),

              // Tombol Bayar — hanya jika pending_payment
              if (order.isPendingPayment) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.payment, size: 16),
                    label: const Text('Bayar Sekarang'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _openPayment(context),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _openPayment(BuildContext context) {
    final url = order.midtransRedirectUrl;
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'URL pembayaran tidak tersedia. Mungkin sudah kadaluarsa.')),
      );
      return;
    }
    context.push('/payment-webview', extra: {
      'orderId': order.id,
      'redirectUrl': url,
    });
  }

  Widget _buildStatusBadge(String status) {
    final s = status.toLowerCase();
    Color color;
    String label;
    if (s == 'pending') {
      color = Colors.orange;
      label = 'Menunggu';
    } else if (s == 'processing') {
      color = Colors.blue;
      label = 'Diproses';
    } else if (s == 'shipped' || s == 'dikirim') {
      color = Colors.lightGreen;
      label = 'Dikirim';
    } else if (s == 'delivered' || s == 'selesai') {
      color = Colors.green;
      label = 'Selesai';
    } else if (s == 'cancelled' || s == 'dibatalkan') {
      color = Colors.red;
      label = 'Dibatalkan';
    } else {
      color = Colors.grey;
      label = status;
    }
    return _Badge(label: label, color: color);
  }

  Widget _buildPaymentBadge(String ps) {
    Color color;
    String label;
    switch (ps.toLowerCase()) {
      case 'paid':
      case 'settlement':
        color = Colors.green;
        label = 'Lunas';
        break;
      case 'pending_payment':
        color = Colors.orange;
        label = 'Belum Bayar';
        break;
      case 'cancelled':
        color = Colors.red;
        label = 'Dibatalkan';
        break;
      case 'failed':
        color = Colors.red;
        label = 'Kadaluarsa';
        break;
      case 'unpaid':
        color = Colors.amber[700]!;
        label = 'Belum Lunas';
        break;
      default:
        color = Colors.grey;
        label = ps;
    }
    return _Badge(label: label, color: color);
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}
