import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';

import '../../../core/data/firestore_service.dart';
import '../domain/flash_sale.dart';

/// Menyimpan daftar event flash sale secara realtime (koleksi `flash_sales`).
/// TIDAK memakai timer notifikasi global — hitung mundur & transisi waktu
/// ditangani oleh widget blok (agar rebuild hanya di subtree blok flash sale).
class FlashSaleProvider with ChangeNotifier {
  final FirestoreService _firestoreService;
  StreamSubscription? _sub;

  List<FlashSale> _events = const [];
  bool _isLoading = true;

  FlashSaleProvider(this._firestoreService) {
    _listen();
  }

  bool get isLoading => _isLoading;
  List<FlashSale> get events => _events;

  /// Event yang ditampilkan di beranda: aktif diprioritaskan, lalu teaser
  /// (cooldown) yang paling dekat mulai.
  FlashSale? pickEvent([DateTime? now]) {
    final t = now ?? DateTime.now();
    FlashSale? active;
    FlashSale? teaser;
    for (final e in _events) {
      switch (e.statusAt(t)) {
        case FlashSaleStatus.active:
          if (active == null || e.startAt.isAfter(active.startAt)) active = e;
          break;
        case FlashSaleStatus.teaser:
          if (teaser == null || e.startAt.isBefore(teaser.startAt)) teaser = e;
          break;
        default:
          break;
      }
    }
    return active ?? teaser;
  }

  /// Event yang SEDANG aktif (harga beli berlaku). null bila tidak ada.
  FlashSale? activeEvent([DateTime? now]) {
    final t = now ?? DateTime.now();
    FlashSale? active;
    for (final e in _events) {
      if (e.statusAt(t) == FlashSaleStatus.active) {
        if (active == null || e.startAt.isAfter(active.startAt)) active = e;
      }
    }
    return active;
  }

  /// Harga flash aktif untuk sebuah produk, atau null.
  double? activeFlashPriceFor(String productId) =>
      activeEvent()?.flashPriceFor(productId);

  void _listen() {
    _sub = _firestoreService.getFlashSalesStream().listen((events) {
      _events = events;
      _isLoading = false;
      notifyListeners();
    }, onError: (error, stackTrace) {
      developer.log('Error mendengarkan flash sale',
          name: 'FlashSaleProvider', error: error, stackTrace: stackTrace);
      _isLoading = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
