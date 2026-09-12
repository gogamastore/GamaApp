import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Popup notifikasi/iklan (pesan ramah) yang muncul saat pertama membuka
/// aplikasi — meniru perilaku popup di halaman web reseller.
///
/// Hanya tampil bila admin mengaktifkannya lewat dokumen Firestore
/// `settings/popup_notification` (diatur dari dashboard web / gogama_office).
/// Tampil **sekali per sesi** (per proses aplikasi). Bisa ditutup lewat tombol
/// ✕ atau ketuk area luar (barrier).
class PromoPopup {
  PromoPopup._();

  static bool _shownThisLaunch = false;

  /// Aman dipanggil dari `initState` via `addPostFrameCallback`.
  static Future<void> maybeShow(BuildContext context) async {
    if (_shownThisLaunch) return;
    _shownThisLaunch = true; // sekali per sesi/app launch

    try {
      final snap = await FirebaseFirestore.instance
          .collection('settings')
          .doc('popup_notification')
          .get();
      final d = snap.data();
      if (d == null || d['enabled'] != true) return;
      if (!context.mounted) return;

      final type = d['type'] == 'image' ? 'image' : 'text';

      if (type == 'image') {
        final imageUrl = (d['imageUrl'] ?? '').toString();
        if (imageUrl.isEmpty) return;
        await showDialog<void>(
          context: context,
          barrierDismissible: true,
          builder: (_) => _ImagePopup(imageUrl: imageUrl),
        );
      } else {
        final title = (d['title'] ?? '').toString();
        final subject = (d['subject'] ?? '').toString();
        final body = (d['body'] ?? '').toString();
        if (title.isEmpty && subject.isEmpty && body.isEmpty) return;
        await showDialog<void>(
          context: context,
          barrierDismissible: true,
          builder: (_) => _TextPopup(title: title, subject: subject, body: body),
        );
      }
    } catch (_) {
      // diamkan — jangan ganggu app bila config gagal dimuat
    }
  }
}

class _ImagePopup extends StatelessWidget {
  const _ImagePopup({required this.imageUrl});
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: size.height * 0.70,
              maxWidth: size.width * 0.70,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
                placeholder: (c, u) => const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (c, u, e) => const SizedBox.shrink(),
              ),
            ),
          ),
          Positioned(
            right: -6,
            top: -6,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                iconSize: 20,
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TextPopup extends StatelessWidget {
  const _TextPopup({
    required this.title,
    required this.subject,
    required this.body,
  });
  final String title;
  final String subject;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title.isNotEmpty)
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                if (subject.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    subject,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.grey[700], height: 1.4),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            right: 2,
            top: 2,
            child: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Tutup',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
