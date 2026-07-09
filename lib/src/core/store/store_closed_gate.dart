import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Membungkus seluruh aplikasi dan mendengarkan dokumen `settings/operational`
/// secara real-time (dokumen yang sama dengan web).
///
/// Saat admin mengaktifkan "Libur Toko" (`isClosed == true`), gate ini
/// menampilkan pemberitahuan yang TIDAK bisa ditutup di atas aplikasi
/// (barrier non-dismissible + tombol back ditahan). Pemberitahuan hilang
/// otomatis begitu admin menonaktifkan Libur (`isClosed == false`).
class StoreClosedGate extends StatelessWidget {
  final Widget child;

  const StoreClosedGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final docStream = FirebaseFirestore.instance
        .collection('settings')
        .doc('operational')
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: docStream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final isClosed = data?['isClosed'] == true;
        final message = ((data?['message'] as String?) ?? '').trim();

        return Stack(
          children: [
            child,
            if (isClosed) _StoreClosedOverlay(message: message),
          ],
        );
      },
    );
  }
}

class _StoreClosedOverlay extends StatelessWidget {
  final String message;

  const _StoreClosedOverlay({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // PopScope menahan tombol back; ModalBarrier memblokir semua interaksi
    // dengan aplikasi di belakang dan tidak bisa ditutup dengan ketukan.
    return Positioned.fill(
      child: PopScope(
        canPop: false,
        child: Stack(
          children: [
            const ModalBarrier(dismissible: false, color: Colors.black87),
            Center(
              child: Container(
                margin: const EdgeInsets.all(28),
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.campaign,
                        size: 40,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Toko Sedang Libur',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      message.isNotEmpty
                          ? message
                          : 'Toko sedang tidak beroperasi untuk sementara waktu.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.grey[700]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Anda dapat berbelanja kembali setelah toko dibuka.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.grey[500]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
