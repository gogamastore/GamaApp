import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../application/checkout_provider.dart';

/// Menampilkan detail pengiriman (read-only) berdasarkan alamat tersimpan
/// yang dipilih + satu field opsional catatan untuk kurir.
class DeliveryInfoWidget extends StatefulWidget {
  const DeliveryInfoWidget({super.key});

  @override
  State<DeliveryInfoWidget> createState() => _DeliveryInfoWidgetState();
}

class _DeliveryInfoWidgetState extends State<DeliveryInfoWidget> {
  late final CheckoutProvider _checkoutProvider;
  late final TextEditingController _instructionsController;

  @override
  void initState() {
    super.initState();
    _checkoutProvider = context.read<CheckoutProvider>();
    _instructionsController = TextEditingController(
      text: _checkoutProvider.deliveryInfo.specialInstructions,
    );
  }

  @override
  void dispose() {
    _instructionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CheckoutProvider>();
    final info = provider.deliveryInfo;
    final addr = provider.selectedAddress;

    final String name =
        (addr != null && addr.name.isNotEmpty) ? addr.name : info.recipientName;
    final String phone =
        (addr != null && addr.phone.isNotEmpty) ? addr.phone : info.phoneNumber;

    // Alamat tujuan lengkap + kode pos
    final String fullAddress = addr != null
        ? [
            addr.address,
            addr.city,
            [addr.province, addr.postalCode]
                .where((s) => s.trim().isNotEmpty)
                .join(' '),
          ].where((s) => s.trim().isNotEmpty).join(', ')
        : [info.address, info.city, info.postalCode]
            .where((s) => s.trim().isNotEmpty)
            .join(', ');

    final bool hasAddress = name.isNotEmpty || fullAddress.isNotEmpty;

    if (!hasAddress) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey[50],
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          children: [
            Icon(Icons.location_off_outlined, size: 32, color: Colors.grey[400]),
            const SizedBox(height: 8),
            const Text('Belum ada alamat tersimpan',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'Tambahkan alamat pengiriman terlebih dahulu untuk melanjutkan.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => context.push('/profile/address'),
              icon: const Icon(Icons.add_location_alt_outlined, size: 18),
              label: const Text('Tambah Alamat'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.grey[50],
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('Nama Penerima', name.isNotEmpty ? name : '-'),
              const SizedBox(height: 10),
              _row('Nomor Telepon', phone.isNotEmpty ? phone : '-'),
              const SizedBox(height: 10),
              _row('Alamat Tujuan', fullAddress.isNotEmpty ? fullAddress : '-'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _instructionsController,
          decoration: const InputDecoration(
            labelText: 'Catatan untuk kurir (opsional)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          maxLines: 2,
          onChanged: _checkoutProvider.updateSpecialInstructions,
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(label,
              style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(value,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
