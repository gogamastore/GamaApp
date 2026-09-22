import 'dart:developer' as developer;
import 'package:cloud_functions/cloud_functions.dart';

/// Normalisasi nomor Indonesia ke format 62xxxxxxxxxx (tanpa '+').
/// Menerima input "08123...", "+62 812...", "62812...", atau "8123...".
/// Server melakukan normalisasi yang sama — ini untuk tampilan & validasi awal.
String normalizeWhatsappNumber(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';
  if (digits.startsWith('620')) return '62${digits.substring(3)}';
  if (digits.startsWith('62')) return digits;
  if (digits.startsWith('0')) return '62${digits.substring(1)}';
  if (digits.startsWith('8')) return '62$digits';
  return digits;
}

bool isValidWhatsappNumber(String raw) {
  return RegExp(r'^628\d{7,12}$').hasMatch(normalizeWhatsappNumber(raw));
}

String maskWhatsappNumber(String raw) {
  final phone = normalizeWhatsappNumber(raw);
  if (phone.length < 6) return phone;
  return '${phone.substring(0, 4)}****${phone.substring(phone.length - 3)}';
}

/// Hasil permintaan pengiriman OTP.
class WhatsappOtpSendResult {
  final String maskedPhone;
  final int expiresInSeconds;
  final int resendAfterSeconds;

  WhatsappOtpSendResult({
    required this.maskedPhone,
    required this.expiresInSeconds,
    required this.resendAfterSeconds,
  });
}

/// Error yang sudah diterjemahkan ke pesan siap tampil untuk pembeli.
class WhatsappVerificationException implements Exception {
  final String code;
  final String message;

  WhatsappVerificationException({required this.code, required this.message});

  @override
  String toString() => message;
}

/// Jembatan ke Cloud Functions `sendWhatsappOtp` & `verifyWhatsappOtp`.
class WhatsappVerificationService {
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );

  /// Kirim kode OTP ke nomor WhatsApp pembeli.
  Future<WhatsappOtpSendResult> sendOtp({String? phone}) async {
    try {
      final callable = _functions.httpsCallable('sendWhatsappOtp');
      final result = await callable.call<Map<dynamic, dynamic>>(
        phone == null ? <String, dynamic>{} : {'phone': phone},
      );
      final data = result.data;
      return WhatsappOtpSendResult(
        maskedPhone: (data['phone'] as String?) ?? '',
        expiresInSeconds: (data['expiresInSeconds'] as num?)?.toInt() ?? 300,
        resendAfterSeconds: (data['resendAfterSeconds'] as num?)?.toInt() ?? 60,
      );
    } on FirebaseFunctionsException catch (e) {
      throw _mapException(e, 'Gagal mengirim kode verifikasi.');
    } catch (e, s) {
      developer.log('sendWhatsappOtp error',
          name: 'WhatsappVerificationService', error: e, stackTrace: s);
      throw WhatsappVerificationException(
        code: 'unknown',
        message: 'Terjadi kesalahan. Periksa koneksi Anda lalu coba lagi.',
      );
    }
  }

  /// Konfirmasi kode OTP. Bila benar, Cloud Function menandai
  /// `whatsappStatus: 'verified'` pada dokumen `user/{uid}`.
  Future<void> verifyOtp(String code) async {
    try {
      final callable = _functions.httpsCallable('verifyWhatsappOtp');
      await callable.call<Map<dynamic, dynamic>>({'code': code});
    } on FirebaseFunctionsException catch (e) {
      throw _mapException(e, 'Verifikasi gagal.');
    } catch (e, s) {
      developer.log('verifyWhatsappOtp error',
          name: 'WhatsappVerificationService', error: e, stackTrace: s);
      throw WhatsappVerificationException(
        code: 'unknown',
        message: 'Terjadi kesalahan. Periksa koneksi Anda lalu coba lagi.',
      );
    }
  }

  WhatsappVerificationException _mapException(
      FirebaseFunctionsException e, String fallback) {
    developer.log(
      'Cloud Function menolak permintaan verifikasi WhatsApp',
      name: 'WhatsappVerificationService',
      error: '${e.code}: ${e.message}',
    );
    // Pesan dari Cloud Function sudah berbahasa Indonesia dan aman ditampilkan.
    final message = e.message;
    return WhatsappVerificationException(
      code: e.code,
      message: (message == null || message.isEmpty) ? fallback : message,
    );
  }
}
