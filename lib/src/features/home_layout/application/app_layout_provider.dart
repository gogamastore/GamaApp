import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/theme_provider.dart';
import '../domain/app_layout.dart';

/// Mendengarkan dokumen `settings/app_layout` secara real-time. Dokumen ini
/// ditulis oleh tombol "Publish" di halaman App Builder web admin, sehingga
/// perubahan desain langsung tampil di aplikasi tanpa rilis ulang.
class AppLayoutProvider with ChangeNotifier {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  Timer? _readyFallback;

  AppLayout _layout = AppLayout.defaults();
  ThemeData _theme = ThemeProvider.lightTheme;
  String _designSignature = '';
  bool _isReady = false;
  bool _hasConfig = false;

  AppLayoutProvider() {
    _subscription = FirebaseFirestore.instance
        .collection('settings')
        .doc('app_layout')
        .snapshots()
        .listen(_onSnapshot, onError: (Object error, StackTrace stackTrace) {
      developer.log('Gagal memuat layout aplikasi',
          name: 'AppLayoutProvider', error: error, stackTrace: stackTrace);
      _markReady();
    });

    // Jika offline dan belum ada cache, jangan tahan beranda terlalu lama —
    // tampilkan susunan default.
    _readyFallback = Timer(const Duration(seconds: 4), _markReady);
  }

  AppLayout get layout => _layout;
  AppDesign get design => _layout.design;
  ThemeData get theme => _theme;

  /// false sampai snapshot pertama (cache/server) diterima, supaya beranda
  /// tidak sempat menampilkan susunan default lalu berganti.
  bool get isReady => _isReady;

  /// true hanya bila dokumen `settings/app_layout` BENAR-BENAR ada (sudah
  /// di-Publish admin). Dipakai halaman Katalog agar tampilan bawaan tidak
  /// berubah sebelum ada konfigurasi yang diterbitkan.
  bool get hasConfig => _hasConfig;

  void _onSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    _hasConfig = snapshot.exists && data != null;
    try {
      _layout = AppLayout.fromMap(data);
    } catch (e, st) {
      developer.log('Dokumen app_layout tidak valid, memakai default',
          name: 'AppLayoutProvider', error: e, stackTrace: st);
      _layout = AppLayout.defaults();
    }

    // Bangun ulang ThemeData hanya bila bagian desain berubah (font Google
    // Fonts relatif mahal untuk dibuat ulang setiap snapshot).
    final signature = _signatureOf(data?['design']);
    if (signature != _designSignature) {
      _designSignature = signature;
      _theme = ThemeProvider.buildTheme(_layout.design);
    }

    _isReady = true;
    _readyFallback?.cancel();
    notifyListeners();
  }

  void _markReady() {
    if (_isReady) return;
    _isReady = true;
    notifyListeners();
  }

  String _signatureOf(dynamic design) {
    try {
      return jsonEncode(design);
    } catch (_) {
      return design.toString();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _readyFallback?.cancel();
    super.dispose();
  }
}
