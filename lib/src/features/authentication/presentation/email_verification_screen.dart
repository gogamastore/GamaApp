import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key, required this.email});

  final String email;

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  Timer? _pollTimer;
  bool _isChecking = false;
  bool _isResending = false;

  @override
  void initState() {
    super.initState();
    // Cek status verifikasi secara berkala agar pengguna otomatis diarahkan
    // ke halaman login begitu tautan verifikasi di email mereka diklik.
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkVerification(silent: true),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkVerification({bool silent = false}) async {
    if (_isChecking) return;
    setState(() => _isChecking = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        // Sesi sudah tidak ada, kembalikan ke halaman login.
        _pollTimer?.cancel();
        if (mounted) context.go('/login');
        return;
      }

      await user.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser;

      if (refreshedUser != null && refreshedUser.emailVerified) {
        _pollTimer?.cancel();

        // Perbarui status verifikasi di Firestore sebelum sign out
        // (setelah sign out, rules Firestore tidak lagi mengizinkan tulis).
        await FirebaseFirestore.instance
            .collection('user')
            .doc(refreshedUser.uid)
            .update({'verificationStatus': 'verified'});
        await FirebaseAuth.instance.signOut();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email berhasil diverifikasi! Silakan masuk.'),
          ),
        );
        context.go('/login');
      } else if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Email belum diverifikasi. Silakan cek inbox (atau folder spam) Anda.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal memeriksa status verifikasi. Coba lagi.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _resendEmail() async {
    setState(() => _isResending = true);
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Email verifikasi telah dikirim ulang.')),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Gagal mengirim ulang email verifikasi.';
      if (e.code == 'too-many-requests') {
        message = 'Terlalu banyak percobaan. Silakan coba lagi nanti.';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  Future<void> _cancelRegistration() async {
    _pollTimer?.cancel();
    // Status di Firestore tetap 'pending' — halaman login yang akan
    // mengingatkan user untuk verifikasi saat mereka mencoba masuk.
    await FirebaseAuth.instance.signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _cancelRegistration();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Verifikasi Email'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _cancelRegistration,
          ),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.mark_email_unread_outlined,
                    size: 96,
                    color: Colors.teal,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Verifikasi Email Anda',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Kami telah mengirimkan tautan verifikasi ke:',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.email,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Silakan buka email Anda dan klik tautan verifikasi.'
                    'Jika Tidak menerima email, periksa folder spam',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _isChecking ? null : () => _checkVerification(),
                    child: _isChecking
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Saya Sudah Verifikasi'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _isResending ? null : _resendEmail,
                    child: _isResending
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Kirim Ulang Email Verifikasi'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _cancelRegistration,
                    child: const Text('Kembali ke Login'),
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
