import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/checkout_provider.dart';

class PaymentMethodWidget extends StatelessWidget {
  const PaymentMethodWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final checkoutProvider = context.watch<CheckoutProvider>();
    final isCourierSelected =
        checkoutProvider.selectedShipping?.id == 'courier';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Midtrans ─────────────────────────────────────────
        RadioListTile<String>(
          title: const Text('Pembayaran Online'),
          subtitle: const Text('Kartu Kredit, GoPay, QRIS, Virtual Account'),
          value: 'midtrans',
          groupValue: checkoutProvider.selectedPaymentMethod,
          onChanged: (value) {
            if (value != null) {
              context.read<CheckoutProvider>().selectPaymentMethod(value);
            }
          },
        ),

        // ── Bank Transfer ────────────────────────────────────
        RadioListTile<String>(
          title: const Text('Transfer Bank'),
          subtitle: const Text('Transfer ke salah satu rekening kami'),
          value: 'bank_transfer',
          groupValue: checkoutProvider.selectedPaymentMethod,
          onChanged: (value) {
            if (value != null) {
              context.read<CheckoutProvider>().selectPaymentMethod(value);
            }
          },
        ),
        if (checkoutProvider.selectedPaymentMethod == 'bank_transfer')
          _buildBankTransferDetails(context),

        // ── COD ──────────────────────────────────────────────
        RadioListTile<String>(
          title: Text(
            'COD (Bayar di Tempat)',
            style: TextStyle(
              color: isCourierSelected ? Colors.grey : null,
            ),
          ),
          subtitle: Text(
            'Siapkan uang pas saat pengambilan'
            '${isCourierSelected ? '\n(Tidak tersedia untuk pengiriman kurir)' : ''}',
            style: TextStyle(
              color: isCourierSelected ? Colors.grey : null,
            ),
          ),
          value: 'cod',
          groupValue: checkoutProvider.selectedPaymentMethod,
          // Nonaktifkan jika kurir dipilih atau jika ada tarif biteship terpilih
          onChanged: isCourierSelected ||
                  checkoutProvider.selectedBiteshipRate != null
              ? null
              : (value) {
                  if (value != null) {
                    context.read<CheckoutProvider>().selectPaymentMethod(value);
                  }
                },
        ),
      ],
    );
  }

  Widget _buildBankTransferDetails(BuildContext context) {
    final checkoutProvider = context.watch<CheckoutProvider>();

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.withAlpha(12), // 5% opacity
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withAlpha(51)), // 20% opacity
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Silakan transfer ke rekening berikut:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ...checkoutProvider.bankAccounts.map(
            (account) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const Icon(Icons.account_balance),
                title: Text(account.bankName),
                subtitle: Text(
                  '${account.accountNumber}\na/n ${account.accountHolder}',
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Colors.grey.shade700, size: 20),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Pembayaran Hanya dilakukan Setelah pesanan '
                    'Anda di Proses oleh Admin',
                    style: TextStyle(color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
