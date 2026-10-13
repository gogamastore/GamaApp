import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/whatsapp_verification_popup.dart';
import '../../authentication/data/auth_service.dart';
import '../../home_layout/application/app_layout_provider.dart';
import '../../home_layout/domain/app_layout.dart';
import '../../home_layout/presentation/home_block_view.dart';

/// Beranda. Susunan & tampilan bloknya diatur admin dari App Builder di web
/// (dokumen Firestore `settings/app_layout`); bila belum pernah dipublish,
/// dipakai susunan default (banner, brand, flash sale, trending, tombol
/// katalog).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Peringatan verifikasi WhatsApp hanya ditampilkan sekali per sesi beranda,
  // supaya tidak muncul berulang setiap kali tab Beranda dibuka kembali.
  bool _whatsappPopupShown = false;

  /// Tampilkan popup bila `whatsappStatus` pada dokumen user masih
  /// 'unverified'. Dipanggil setelah frame pertama selesai dibangun.
  void _maybeShowWhatsappPopup(AuthService authService) {
    if (_whatsappPopupShown) return;
    final user = authService.currentUser;
    if (user == null || user.isWhatsappVerified) return;

    _whatsappPopupShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showWhatsappVerificationPopup(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    // listen: true agar pengecekan ikut berjalan begitu data user selesai dimuat.
    _maybeShowWhatsappPopup(Provider.of<AuthService>(context));

    final layoutProvider = context.watch<AppLayoutProvider>();
    if (!layoutProvider.isReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final blocks = layoutProvider.layout.blocks.where((b) => b.enabled).toList();

    // Blok "Induk Kategori" yang disematkan (pinned) ditarik keluar dari area
    // scroll → tetap menempel di atas (sticky) saat halaman di-scroll.
    bool isPinned(HomeBlock b) =>
        b.type == HomeBlockType.parentCategories && b.config.boolean('pinned', false);
    final pinned = blocks.where(isPinned).toList();
    final scrolling = blocks.where((b) => !isPinned(b)).toList();

    // SingleChildScrollView (bukan ListView) supaya blok yang keluar layar
    // tidak di-dispose lalu berlangganan ulang ke Firestore saat kembali.
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final block in pinned)
            Material(
              elevation: 1,
              child: HomeBlockView(key: ValueKey(block.id), block: block),
            ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final block in scrolling)
                    HomeBlockView(key: ValueKey(block.id), block: block),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
