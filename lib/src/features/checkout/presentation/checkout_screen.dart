import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../application/checkout_provider.dart';
import '../../cart/application/cart_provider.dart';
import '../../authentication/data/auth_service.dart';
import '../../../core/data/firestore_service.dart';
import '../data/biteship_service.dart';
import 'widgets/delivery_info_widget.dart';
import 'widgets/biteship_rates_widget.dart';

class CheckoutScreen extends StatelessWidget {
  const CheckoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CheckoutProvider(
        authService: context.read<AuthService>(),
        firestoreService: context.read<FirestoreService>(),
        cartProvider: context.read<CartProvider>(),
      )..initialize(),
      child: Consumer<CheckoutProvider>(
        builder: (context, provider, child) {
          if (provider.isInitializing) {
            return Scaffold(
              appBar: AppBar(title: const Text('Checkout')),
              body: const Center(child: CircularProgressIndicator()),
            );
          }

          return Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.pop(),
                ),
                title: const Text('Checkout'),
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAddressSection(context),
                    const SizedBox(height: 16),
                    _buildDeliveryFormSection(context),
                    const SizedBox(height: 16),
                    _buildShippingSection(context),
                    const SizedBox(height: 16),
                    _buildPaymentSection(context),
                    const SizedBox(height: 16),
                    _buildOrderSummary(context),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              bottomNavigationBar: _buildBottomBar(context),
            ),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────
  Widget _buildCard({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: child,
      );

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      );

  // ─────────────────────────────────────────────────────────────
  // Section 1: Alamat tersimpan + dropdown dengan auto Biteship
  // ─────────────────────────────────────────────────────────────
  Widget _buildAddressSection(BuildContext context) {
    final provider = context.watch<CheckoutProvider>();
    if (provider.userAddresses.isEmpty) return const SizedBox.shrink();

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Alamat Tersimpan'),
          DropdownButtonFormField<String>(
            value: provider.selectedAddress?.id,
            hint: const Text('Pilih alamat Anda'),
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: (String? selectedId) {
              if (selectedId == null) return;
              final addr = provider.userAddresses.firstWhere(
                (a) => a.id == selectedId,
              );
              // Set alamat + auto-fetch rates (coba koordinat dulu, lalu kota)
              context
                  .read<CheckoutProvider>()
                  .selectSavedAddressAndLoadRates(addr);
            },
            items: provider.userAddresses.map((addr) {
              return DropdownMenuItem<String>(
                value: addr.id,
                child: Text(
                  '${addr.label.isNotEmpty ? addr.label : addr.name} — ${addr.city}',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
          ),

          // Info koordinat
          if (provider.selectedAddress != null) ...[
            const SizedBox(height: 8),
            _buildCoordInfo(provider),
          ],
        ],
      ),
    );
  }

  Widget _buildCoordInfo(CheckoutProvider provider) {
    final addr = provider.selectedAddress!;
    if (addr.hasCoordinates) {
      return Row(
        children: [
          Icon(Icons.location_on, size: 14, color: Colors.green[600]),
          const SizedBox(width: 4),
          Text(
            'Koordinat GPS tersedia',
            style: TextStyle(fontSize: 12, color: Colors.green[700]),
          ),
        ],
      );
    }
    return Row(
      children: [
        Icon(Icons.location_off, size: 14, color: Colors.orange[600]),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            'Belum ada GPS — Edit alamat untuk tambahkan lokasi peta',
            style: TextStyle(fontSize: 12, color: Colors.orange[700]),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Section 2: Form alamat + search area Biteship manual
  // ─────────────────────────────────────────────────────────────
  Widget _buildDeliveryFormSection(BuildContext context) {
    final provider = context.watch<CheckoutProvider>();
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(provider.userAddresses.isEmpty
              ? 'Alamat Pengiriman'
              : 'Atau Isi Alamat Baru'),

          // Search kota Biteship (juga bisa diketik manual)
          BiteshipAreaSearchField(
            label: 'Cari Kota / Kecamatan Tujuan',
            onAreaSelected: (area) {
              context.read<CheckoutProvider>().onDestinationAreaSelected(area);
            },
            initialArea: provider.selectedDestinationArea,
          ),

          // Info area yang sudah terpilih
          if (provider.selectedDestinationArea != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.check_circle, size: 14, color: Colors.green[600]),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Tujuan: ${provider.selectedDestinationArea!.name}, '
                    '${provider.selectedDestinationArea!.adminName}',
                    style: TextStyle(fontSize: 12, color: Colors.green[700]),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),
          const DeliveryInfoWidget(),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Section 3: Pilih pengiriman
  // ─────────────────────────────────────────────────────────────
  Widget _buildShippingSection(BuildContext context) {
    final provider = context.watch<CheckoutProvider>();
    final cartProvider = context.watch<CartProvider>();

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Pilih Layanan Pengiriman'),

          // ── Ambil di toko ───────────────────────────────────
          _buildPickupOption(context),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),

          // ── Biteship: semua kurir ───────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: const Text('KURIR',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue)),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('JNE · J&T · SiCepat · GoSend · dan lainnya',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Status area tujuan
          if (provider.selectedDestinationArea == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _buildInfoBanner(
                icon: Icons.info_outline,
                color: Colors.blue,
                message: provider.userAddresses.isNotEmpty
                    ? 'Pilih alamat tersimpan di atas untuk melihat tarif otomatis, atau ketik nama kota tujuan.'
                    : 'Ketik nama kota/kecamatan tujuan di kolom pencarian di atas.',
              ),
            )
          else ...[
            const SizedBox(height: 12),
            BiteshipRatesWidget(
              destinationAreaId: provider.selectedDestinationArea?.id,
              items: cartProvider.items
                  .map((item) => ShipmentItem(
                        productId: item.productId,
                        name: item.nama,
                        price: item.harga,
                        quantity: item.quantity,
                        weightGram: 200,
                      ))
                  .toList(),
              selectedRate: provider.selectedBiteshipRate,
              onRateSelected: provider.selectBiteshipRate,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPickupOption(BuildContext context) {
    final provider = context.watch<CheckoutProvider>();
    final isSelected = provider.selectedShipping?.id == 'pickup';

    return GestureDetector(
      onTap: () {
        final pickup = provider.shippingOptions.first;
        context.read<CheckoutProvider>().selectShippingOption(pickup);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.07)
              : Colors.grey[50],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.store_outlined,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey[600]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ambil di Toko',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      )),
                  Text('Gratis — ambil langsung di toko',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Section 4: Metode pembayaran
  // ─────────────────────────────────────────────────────────────
  Widget _buildPaymentSection(BuildContext context) {
    final provider = context.watch<CheckoutProvider>();
    final isPickup = provider.selectedShipping?.id == 'pickup';

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Metode Pembayaran'),

          // Midtrans
          _buildPaymentOption(
            context,
            value: 'midtrans',
            icon: Icons.payment,
            iconColor: Colors.blue,
            title: 'Bayar via Midtrans',
            subtitle: 'GoPay · QRIS · VA Bank · Kartu Kredit · Minimarket',
            selectedValue: provider.selectedPaymentMethod,
            onTap: () => context
                .read<CheckoutProvider>()
                .selectPaymentMethod('midtrans'),
          ),

          if (provider.selectedPaymentMethod == 'midtrans') ...[
            const SizedBox(height: 10),
            _buildMidtransGrid(),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Halaman pembayaran akan terbuka setelah Anda menekan "Buat Pesanan & Bayar"',
                      style: TextStyle(fontSize: 11, color: Colors.blue[700]),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // COD hanya jika Ambil di Toko
          if (isPickup) ...[
            const SizedBox(height: 12),
            _buildPaymentOption(
              context,
              value: 'cod',
              icon: Icons.payments_outlined,
              iconColor: Colors.green,
              title: 'COD — Bayar di Tempat',
              subtitle: 'Siapkan uang pas saat pengambilan di toko',
              selectedValue: provider.selectedPaymentMethod,
              onTap: () =>
                  context.read<CheckoutProvider>().selectPaymentMethod('cod'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentOption(
    BuildContext context, {
    required String value,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String selectedValue,
    required VoidCallback onTap,
  }) {
    final isSelected = selectedValue == value;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              isSelected ? iconColor.withValues(alpha: 0.07) : Colors.grey[50],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? iconColor : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isSelected ? iconColor : null)),
                  Text(subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isSelected ? iconColor : Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMidtransGrid() {
    final methods = [
      ('GoPay', Icons.account_balance_wallet, Colors.green),
      ('ShopeePay', Icons.shopping_bag, Colors.orange),
      ('QRIS', Icons.qr_code, Colors.purple),
      ('BCA VA', Icons.account_balance, Colors.blue),
      ('BNI VA', Icons.account_balance, Colors.orange[700]!),
      ('BRI VA', Icons.account_balance, Colors.blue[800]!),
      ('Mandiri', Icons.account_balance, Colors.yellow[800]!),
      ('Indomaret', Icons.store, Colors.red),
      ('Alfamart', Icons.store, Colors.red[800]!),
      ('Kartu Kredit', Icons.credit_card, Colors.teal),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: methods
          .map((m) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: m.$3.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: m.$3.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(m.$2, size: 13, color: m.$3),
                    const SizedBox(width: 4),
                    Text(m.$1,
                        style: TextStyle(
                            fontSize: 11,
                            color: m.$3,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ))
          .toList(),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Section 5: Ringkasan pesanan
  // ─────────────────────────────────────────────────────────────
  Widget _buildOrderSummary(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final currency =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Ringkasan Pesanan'),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cart.items.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 20, thickness: 0.5),
            itemBuilder: (context, index) {
              final item = cart.items[index];
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      item.gambar,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 56,
                        height: 56,
                        color: Colors.grey[200],
                        child: const Icon(Icons.image_not_supported,
                            color: Colors.grey),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.nama,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text(
                            '${item.quantity} × ${currency.format(item.harga)}',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[600])),
                        const SizedBox(height: 4),
                        Text(currency.format(item.quantity * item.harga),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Bottom bar
  // ─────────────────────────────────────────────────────────────
  Widget _buildBottomBar(BuildContext context) {
    final provider = context.watch<CheckoutProvider>();
    final currency =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    final hasShipping = provider.selectedShipping != null ||
        provider.selectedBiteshipRate != null;

    return Builder(
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Subtotal', style: TextStyle(color: Colors.grey[600])),
                Text(currency.format(provider.subtotal)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Pengiriman', style: TextStyle(color: Colors.grey[600])),
                Text(
                  hasShipping
                      ? currency.format(provider.shippingCost)
                      : 'Belum dipilih',
                  style: TextStyle(
                    color: hasShipping ? null : Colors.orange,
                    fontWeight: hasShipping ? null : FontWeight.w500,
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(
                  currency.format(provider.grandTotal),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed:
                    provider.isProcessingOrder || provider.isCreatingPayment
                        ? null
                        : () => _handlePlaceOrder(context),
                child: provider.isProcessingOrder || provider.isCreatingPayment
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Buat Pesanan & Bayar',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            if (!hasShipping) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 13, color: Colors.orange[700]),
                  const SizedBox(width: 4),
                  Text('Pilih layanan pengiriman terlebih dahulu',
                      style:
                          TextStyle(fontSize: 11, color: Colors.orange[700])),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Handler tombol bayar
  // ─────────────────────────────────────────────────────────────
  Future<void> _handlePlaceOrder(BuildContext context) async {
    final provider = context.read<CheckoutProvider>();

    final hasShipping = provider.selectedShipping != null ||
        provider.selectedBiteshipRate != null;

    if (!hasShipping) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Pilih layanan pengiriman terlebih dahulu.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    final orderError = await provider.processOrder();
    if (!context.mounted) return;

    if (orderError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(orderError)));
      return;
    }

    // COD → langsung ke pesanan
    if (provider.selectedPaymentMethod == 'cod') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Pesanan berhasil! Silakan ambil di toko.'),
        backgroundColor: Colors.green,
      ));
      context.go('/profile/orders');
      return;
    }

    final orderId = provider.lastOrderId;
    if (orderId == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal mendapatkan ID pesanan.')));
      return;
    }

    final midtransError = await provider.createMidtransPayment(orderId);
    if (!context.mounted) return;

    if (midtransError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(midtransError)));
      return;
    }

    final redirectUrl = provider.midtransRedirectUrl;
    if (redirectUrl != null && context.mounted) {
      context.push('/payment-webview', extra: {
        'orderId': orderId,
        'redirectUrl': redirectUrl,
      });
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Helper widgets
  // ─────────────────────────────────────────────────────────────
  Widget _buildInfoBanner({
    required IconData icon,
    required Color color,
    required String message,
  }) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child:
                  Text(message, style: TextStyle(fontSize: 12, color: color)),
            ),
          ],
        ),
      );
<<<<<<< HEAD
}
=======
}
>>>>>>> 6d80cf66d5c337a9b7e299e7fc51ad611b995e11
