import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_update_service.dart';

Future<void> _launchUpdateUrl(BuildContext context, String url) async {
  if (url.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tautan pembaruan belum tersedia. Hubungi admin.'),
      ),
    );
    return;
  }
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Membungkus seluruh aplikasi. Saat aplikasi dibuka, gate ini otomatis
/// memeriksa versi aplikasi terhadap Firestore:
///   • forceUpdate aktif & versi usang → layar pemblokir (wajib update)
///   • versi baru tersedia (tidak dipaksa) → notifikasi update yang bisa ditutup
class UpdateGate extends StatefulWidget {
  final Widget child;
  final AppUpdateService? service;

  const UpdateGate({super.key, required this.child, this.service});

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  late final AppUpdateService _service;
  AppUpdateInfo _info = const AppUpdateInfo.none();
  bool _optionalDismissed = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AppUpdateService();
    // Cek otomatis setelah frame pertama (saat aplikasi dibuka).
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final info = await _service.checkForUpdate();
    if (!mounted) return;
    if (info.updateAvailable) {
      setState(() => _info = info);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Versi usang + dipaksa → blokir total.
    if (_info.forceUpdate) {
      return _ForceUpdateScreen(info: _info);
    }

    // Versi baru tersedia (opsional) → tampilkan notifikasi di atas aplikasi.
    final showOptional = _info.updateAvailable && !_optionalDismissed;
    return Stack(
      children: [
        widget.child,
        if (showOptional)
          _OptionalUpdateOverlay(
            info: _info,
            onLater: () => setState(() => _optionalDismissed = true),
          ),
      ],
    );
  }
}

/// Notifikasi update opsional (bisa ditutup / "Nanti").
class _OptionalUpdateOverlay extends StatelessWidget {
  final AppUpdateInfo info;
  final VoidCallback onLater;

  const _OptionalUpdateOverlay({required this.info, required this.onLater});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: Material(
        color: Colors.black54,
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(28),
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.system_update,
                          color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Versi Baru Tersedia',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Tersedia pembaruan aplikasi (versi ${info.latestVersion}). '
                  'Perbarui untuk mendapatkan fitur terbaru dan perbaikan.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: Colors.grey[700]),
                ),
                if (info.releaseNotes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(info.releaseNotes,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.grey[600])),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: onLater, child: const Text('Nanti')),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => _launchUpdateUrl(context, info.updateUrl),
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('Perbarui'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Layar pemblokir wajib update — pengguna tidak bisa melanjutkan.
class _ForceUpdateScreen extends StatelessWidget {
  final AppUpdateInfo info;

  const _ForceUpdateScreen({required this.info});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Blokir tombol back agar pengguna tidak bisa melewati layar ini.
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.system_update,
                        size: 56, color: theme.colorScheme.primary),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Pembaruan Diperlukan',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Versi aplikasi Anda sudah tidak didukung. '
                    'Silakan perbarui ke versi terbaru untuk melanjutkan.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.grey[700]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Versi Anda',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[600])),
                            const SizedBox(height: 2),
                            Text(info.currentVersion,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                        Icon(Icons.arrow_forward, color: Colors.grey[400]),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('Versi Terbaru',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[600])),
                            const SizedBox(height: 2),
                            Text(info.latestVersion,
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (info.releaseNotes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Yang baru:',
                          style: theme.textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 4),
                    Text(info.releaseNotes,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.grey[700])),
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _launchUpdateUrl(context, info.updateUrl),
                      icon: const Icon(Icons.download),
                      label: const Text('Perbarui Sekarang'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
