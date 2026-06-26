import 'dart:async';
import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Layar pembayaran Midtrans Snap — platform-aware.
///
/// ─── Android/iOS ───────────────────────────────────────────────
/// WebViewController embedded. Intercept callback URL Midtrans.
///
/// ─── Web/Chrome ────────────────────────────────────────────────
/// Midtrans dibuka di tab browser baru via url_launcher.
/// Stream Firestore real-time mendeteksi perubahan paymentStatus
/// yang di-update oleh webhook Midtrans (handleMidtransNotification).
/// Tidak ada konfirmasi manual dari user.
///
/// ─── Expire 24 jam ─────────────────────────────────────────────
/// Midtrans akan mengirim webhook `expire` setelah 24 jam jika belum bayar.
/// Webhook → Cloud Function handleMidtransNotification:
///   paymentStatus = 'failed', status = 'Cancelled'
/// Stream Firestore di Flutter mendeteksi ini → redirect ke Tab "Dibatalkan"
/// Cloud Function checkExpiredOrders (scheduled) sebagai backup sweeper.
///
/// Skenario:
///   paymentStatus = 'paid'            → Tab "Diproses"
///   paymentStatus = 'pending_payment' → tetap menunggu
///   paymentStatus = 'failed'/'cancelled' → Tab "Dibatalkan"
///   User tutup manual                 → paymentStatus = 'pending_payment'
///                                       → Tab "Belum Bayar"
class PaymentWebViewScreen extends StatefulWidget {
  final String orderId;
  final String redirectUrl;

  const PaymentWebViewScreen({
    super.key,
    required this.orderId,
    required this.redirectUrl,
  });

  @override
  State<PaymentWebViewScreen> createState() => _PaymentWebViewScreenState();
}

class _PaymentWebViewScreenState extends State<PaymentWebViewScreen> {
  // ── Native WebView (Android/iOS) ──────────────────────────────
  WebViewController? _webController;
  bool _isLoading = true;

  // ── Firestore real-time stream ────────────────────────────────
  StreamSubscription<DocumentSnapshot>? _paymentStream;
  bool _hasNavigated = false;

  // ── Web UI state ──────────────────────────────────────────────
  bool _webLaunched = false;
  String _webStatusMessage = 'Menunggu konfirmasi pembayaran...';
  bool _isPaymentConfirmed = false;

  // ── Midtrans URL patterns (Android/iOS) ──────────────────────
  static const _successPaths = [
    'transaction_status=settlement',
    'transaction_status=capture',
    'status_code=200',
  ];
  static const _pendingPaths = ['transaction_status=pending'];
  static const _failedPaths = [
    'transaction_status=cancel',
    'transaction_status=deny',
    'transaction_status=expire',
  ];

  @override
  void initState() {
    super.initState();
    // Stream Firestore aktif di semua platform
    // Android: intercept URL sebagai primary, stream sebagai backup
    // Web: stream sebagai satu-satunya cara deteksi otomatis
    _startPaymentStream();

    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openInBrowser());
    } else {
      _initNativeWebView();
    }
  }

  @override
  void dispose() {
    _paymentStream?.cancel();
    super.dispose();
  }

  // ── Firestore stream: deteksi status dari webhook Midtrans ────
  void _startPaymentStream() {
    _paymentStream = FirebaseFirestore.instance
        .collection('orders')
        .doc(widget.orderId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists || !mounted || _hasNavigated) return;

      final data = snapshot.data();
      if (data == null) return;
      final paymentStatus = (data['paymentStatus'] as String?) ?? '';

      developer.log(
        'Stream paymentStatus=$paymentStatus',
        name: 'PaymentWebView',
      );

      switch (paymentStatus) {
        case 'paid':
        case 'settlement':
          _onPaymentSuccess();
          break;
        case 'failed':
        case 'cancelled':
          // Webhook Midtrans: expire/cancel/deny → status otomatis berubah
          _onPaymentExpiredOrFailed();
          break;
        case 'pending_payment':
          if (mounted) {
            setState(() => _webStatusMessage =
                'Menunggu konfirmasi pembayaran dari Midtrans...');
          }
          break;
      }
    }, onError: (e) {
      developer.log('Stream error: $e', name: 'PaymentWebView');
    });
  }

  // ── Android/iOS: init WebViewController ──────────────────────
  void _initNativeWebView() {
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _isLoading = p < 100);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _isLoading = false);
        },
        onNavigationRequest: (req) => _handleNativeNavigation(req.url),
      ))
      ..loadRequest(Uri.parse(widget.redirectUrl));
  }

  NavigationDecision _handleNativeNavigation(String url) {
    developer.log('WebView URL: $url', name: 'PaymentWebView');
    if (_successPaths.any((p) => url.contains(p))) {
      _onPaymentSuccess();
      return NavigationDecision.prevent;
    }
    if (_pendingPaths.any((p) => url.contains(p))) {
      _onUserClosedWithoutPaying();
      return NavigationDecision.prevent;
    }
    if (_failedPaths.any((p) => url.contains(p))) {
      _onPaymentExpiredOrFailed();
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  // ── Web: buka Midtrans di tab browser ────────────────────────
  Future<void> _openInBrowser() async {
    final uri = Uri.parse(widget.redirectUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (mounted) setState(() => _webLaunched = true);
    } catch (e) {
      developer.log('launchUrl error: $e', name: 'PaymentWebView');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuka halaman pembayaran: $e')),
        );
      }
    }
  }

  // ── Update Firestore manual (hanya saat user tutup di Android) ─
  Future<void> _updatePaymentStatus(String paymentStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .update({
        'paymentStatus': paymentStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      developer.log(
        'Manual update paymentStatus → $paymentStatus',
        name: 'PaymentWebView',
      );
    } catch (e) {
      developer.log('updatePaymentStatus error: $e', name: 'PaymentWebView');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Skenario pembayaran
  // ─────────────────────────────────────────────────────────────

  // ✅ Berhasil — dari URL intercept (Android) atau stream (semua platform)
  void _onPaymentSuccess() {
    if (_hasNavigated) return;
    _hasNavigated = true;
    _paymentStream?.cancel();

    if (kIsWeb) {
      setState(() {
        _isPaymentConfirmed = true;
        _webStatusMessage = 'Pembayaran berhasil dikonfirmasi!';
      });
    }

    // Di Android via URL intercept: update Firestore
    // Di web: Firestore sudah diupdate webhook — skip update
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _showResultDialog(
        icon: Icons.check_circle_outline,
        iconColor: Colors.green,
        title: 'Pembayaran Berhasil!',
        message:
            'Terima kasih! Pesanan Anda sudah dibayar dan sedang menunggu diproses.',
        buttonLabel: 'Lihat Pesanan',
        onDismiss: () => context.go('/profile/orders?tab=processing'),
      );
    });
  }

  // ⏳ Tutup/back sebelum bayar — hanya dari aksi user manual
  void _onUserClosedWithoutPaying() {
    if (_hasNavigated) return;
    _hasNavigated = true;
    _paymentStream?.cancel();

    _updatePaymentStatus('pending_payment').then((_) {
      if (!mounted) return;
      context.go('/profile/orders?tab=pending_payment');
    });
  }

  // ❌ Expire / gagal / dibatalkan — dari webhook Midtrans atau URL intercept
  // Midtrans webhook (handleMidtransNotification) sudah update Firestore:
  //   paymentStatus = 'failed', status = 'Cancelled'
  // Flutter stream mendeteksi ini dan memanggil fungsi ini
  void _onPaymentExpiredOrFailed() {
    if (_hasNavigated) return;
    _hasNavigated = true;
    _paymentStream?.cancel();

    // Untuk Android via URL intercept: update Firestore dari client
    // Untuk Web via stream: Firestore sudah diupdate webhook — skip
    if (!kIsWeb) {
      _updatePaymentStatus('cancelled');
    }

    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _showResultDialog(
        icon: Icons.cancel_outlined,
        iconColor: Colors.red,
        title: 'Pembayaran Gagal / Kadaluarsa',
        message:
            'Pembayaran tidak berhasil, dibatalkan, atau sudah melewati batas waktu 24 jam.\n'
            'Pesanan secara otomatis dibatalkan.',
        buttonLabel: 'OK',
        onDismiss: () => context.go('/profile/orders?tab=cancelled'),
      );
    });
  }

  void _showResultDialog({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
    required String buttonLabel,
    required VoidCallback onDismiss,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: iconColor),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], height: 1.4),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                onDismiss();
              },
              child: Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }

  void _showCancelConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keluar dari Pembayaran?'),
        content: const Text(
          'Pembayaran belum selesai. Pesanan akan disimpan di tab "Belum Bayar" '
          'dan bisa dibayar kembali selama belum melewati batas waktu 24 jam.',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            child: const Text('Lanjutkan Bayar'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          TextButton(
            child: Text(
              'Keluar',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _onUserClosedWithoutPaying();
            },
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return _buildWebFallback();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showCancelConfirmation();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pembayaran'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _showCancelConfirmation,
          ),
        ),
        body: Stack(
          children: [
            if (_webController != null)
              WebViewWidget(controller: _webController!),
            if (_isLoading) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }

  // ── Web fallback UI — auto-detect via Firestore stream ────────
  Widget _buildWebFallback() {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showCancelConfirmation();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Konfirmasi Pembayaran'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _showCancelConfirmation,
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Icon status ──────────────────────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: _isPaymentConfirmed
                    ? const Icon(Icons.check_circle,
                        key: ValueKey('success'), size: 80, color: Colors.green)
                    : Icon(
                        _webLaunched
                            ? Icons.open_in_browser
                            : Icons.hourglass_top_rounded,
                        key: ValueKey(_webLaunched ? 'launched' : 'loading'),
                        size: 80,
                        color: _webLaunched ? Colors.blue : Colors.grey,
                      ),
              ),
              const SizedBox(height: 24),

              // ── Pesan status (auto dari stream) ──────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _webStatusMessage,
                  key: ValueKey(_webStatusMessage),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),

              if (!_isPaymentConfirmed) ...[
                Text(
                  'Selesaikan pembayaran di tab browser yang sudah terbuka.\n'
                  'Halaman ini akan otomatis memperbarui status setelah pembayaran dikonfirmasi.\n'
                  'Batas waktu pembayaran: 24 jam.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], height: 1.5),
                ),
                const SizedBox(height: 12),

                // Indikator stream aktif
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.grey[400],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Memantau status pembayaran secara real-time...',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Buka ulang jika browser tertutup
                TextButton.icon(
                  icon: const Icon(Icons.open_in_browser, size: 16),
                  label: const Text('Buka Ulang Halaman Pembayaran'),
                  onPressed: _openInBrowser,
                ),
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),

                // Bayar nanti
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Bayar Nanti (Simpan Pesanan)'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _onUserClosedWithoutPaying,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
