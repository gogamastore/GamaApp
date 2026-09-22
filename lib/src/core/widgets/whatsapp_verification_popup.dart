import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Peringatan yang muncul di beranda ketika dokumen `user/{uid}` masih
/// berstatus `whatsappStatus: 'unverified'`. Tombol utama mengarahkan pembeli
/// ke Profil Saya, tempat tombol "Verifikasi" berada.
Future<void> showWhatsappVerificationPopup(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.shield_outlined,
                color: Colors.orange, size: 32),
          ),
          const SizedBox(height: 12),
          const Text(
            'Verifikasi WhatsApp',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: const Text(
        'Nomor WhatsApp Anda belum terverifikasi. Silakan verifikasi '
        'WhatsApp Anda sebelum melakukan pemesanan agar kami dapat '
        'menghubungi Anda terkait status pesanan dan pengiriman.',
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Nanti Saja'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            // Arahkan ke menu Profil → Profil Saya.
            context.go('/profile/edit');
          },
          child: const Text('Verifikasi Sekarang'),
        ),
      ],
    ),
  );
}
