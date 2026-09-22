import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../authentication/data/auth_service.dart';
import '../../data/whatsapp_verification_service.dart';

/// Kolom nomor WhatsApp lengkap dengan alur verifikasi OTP:
/// tombol "Verifikasi" → kotak kode + tombol "Konfirmasi" → centang biru.
///
/// [controller] berisi nomor TANPA kode negara (mis. "8123456789"), sesuai
/// tampilan `prefixText: '+62 '` pada form profil.
class WhatsappVerificationField extends StatefulWidget {
  const WhatsappVerificationField({
    super.key,
    required this.controller,
    required this.verifiedNumber,
    required this.isVerifiedStatus,
    this.enabled = true,
  });

  final TextEditingController controller;

  /// Nomor yang tersimpan di Firestore (format 62xxxxxxxxxx).
  final String verifiedNumber;

  /// `true` bila `whatsappStatus` pada dokumen user bernilai 'verified'.
  final bool isVerifiedStatus;

  final bool enabled;

  @override
  State<WhatsappVerificationField> createState() =>
      _WhatsappVerificationFieldState();
}

class _WhatsappVerificationFieldState extends State<WhatsappVerificationField> {
  final _service = WhatsappVerificationService();
  final _codeController = TextEditingController();

  bool _otpOpen = false;
  bool _sending = false;
  bool _confirming = false;
  int _cooldown = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    // Tombol "Verifikasi" ikut hidup/mati saat nomor diketik ulang.
    widget.controller.addListener(_onNumberChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onNumberChanged);
    _cooldownTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _onNumberChanged() {
    if (mounted) setState(() {});
  }

  /// Nomor dianggap terverifikasi hanya bila status di Firestore 'verified'
  /// DAN nomor pada kolom masih sama dengan nomor yang dulu diverifikasi.
  bool get _isVerified =>
      widget.isVerifiedStatus &&
      normalizeWhatsappNumber(widget.controller.text) ==
          normalizeWhatsappNumber(widget.verifiedNumber);

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _cooldown--;
        if (_cooldown <= 0) timer.cancel();
      });
    });
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
      ),
    );
  }

  Future<void> _sendOtp() async {
    final phone = normalizeWhatsappNumber(widget.controller.text);
    if (!isValidWhatsappNumber(phone)) {
      _showMessage('Nomor WhatsApp tidak valid. Contoh: 8123456789.',
          isError: true);
      return;
    }

    setState(() => _sending = true);
    try {
      final result = await _service.sendOtp(phone: phone);
      if (!mounted) return;
      setState(() {
        _otpOpen = true;
        _codeController.clear();
      });
      _startCooldown(result.resendAfterSeconds);
      _showMessage('Kode verifikasi dikirim ke WhatsApp ${result.maskedPhone}.');
    } on WhatsappVerificationException catch (e) {
      _showMessage(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _confirmOtp() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      _showMessage('Masukkan 6 digit kode verifikasi.', isError: true);
      return;
    }

    setState(() => _confirming = true);
    try {
      await _service.verifyOtp(code);
      // Muat ulang dokumen user agar centang biru langsung tampil.
      if (mounted) await context.read<AuthService>().reloadUser();
      if (!mounted) return;
      setState(() {
        _otpOpen = false;
        _codeController.clear();
      });
      _showMessage('Nomor WhatsApp Anda berhasil diverifikasi.');
    } on WhatsappVerificationException catch (e) {
      _showMessage(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final verified = _isVerified;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: widget.controller,
          enabled: widget.enabled,
          decoration: InputDecoration(
            labelText: 'WhatsApp *',
            prefixText: '+62 ',
            border: const OutlineInputBorder(),
            hintText: '8123456789',
            suffixIcon: verified
                ? const Tooltip(
                    message: 'Nomor WhatsApp terverifikasi',
                    child: Icon(Icons.verified, color: Color(0xFF1D9BF0)),
                  )
                : null,
          ),
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Nomor WhatsApp tidak boleh kosong';
            }
            if (!RegExp(r'^\d{9,13}$').hasMatch(value)) {
              return 'Format nomor tidak valid';
            }
            return null;
          },
        ),
        const SizedBox(height: 8),
        if (verified)
          const Padding(
            padding: EdgeInsets.only(left: 12.0),
            child: Row(
              children: [
                Icon(Icons.verified, size: 16, color: Color(0xFF1D9BF0)),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Nomor WhatsApp sudah terverifikasi.',
                    style: TextStyle(color: Color(0xFF1D9BF0), fontSize: 12),
                  ),
                ),
              ],
            ),
          )
        else ...[
          const Padding(
            padding: EdgeInsets.only(left: 12.0),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 16, color: Colors.orange),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Belum terverifikasi. Verifikasi diperlukan sebelum memesan.',
                    style: TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed:
                  (_sending || _cooldown > 0 || !widget.enabled) ? null : _sendOtp,
              icon: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_user_outlined, size: 18),
              label: Text(
                _cooldown > 0
                    ? 'Kirim Ulang ($_cooldown dtk)'
                    : _otpOpen
                        ? 'Kirim Ulang Kode'
                        : 'Verifikasi',
              ),
            ),
          ),
        ],
        if (_otpOpen && !verified) _buildOtpBox(context),
      ],
    );
  }

  Widget _buildOtpBox(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kode Verifikasi',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Masukkan 6 digit kode yang kami kirim ke WhatsApp '
            '${maskWhatsappNumber(widget.controller.text)}. Kode berlaku 5 menit.',
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                    fontSize: 20,
                    letterSpacing: 8,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    counterText: '',
                    hintText: '······',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: (_confirming || _codeController.text.length != 6)
                    ? null
                    : _confirmOtp,
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                ),
                child: _confirming
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Konfirmasi'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
