import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myapp/src/features/products/domain/product.dart';

class Promotion {
  final String id;
  final String productId;
  final double discountPrice;
  final DateTime startDate;
  final DateTime endDate;

  Promotion({
    required this.id,
    required this.productId,
    required this.discountPrice,
    required this.startDate,
    required this.endDate,
  });

  factory Promotion.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    // --- PERANGKAP & PENGAMAN DATA NaN ---
    // Harga promo bisa tersimpan sebagai number ATAU string (web admin),
    // jadi pakai parser harga yang sama dengan produk.
    double price = Product.parsePrice(data['discountPrice']);

    if (price.isNaN) {
      developer.log(
        '[DATA PROMO RUSAK] Ditemukan nilai NaN pada field \'discountPrice\'. Nilai diganti menjadi 0.0 untuk mencegah crash. Harap perbaiki data di Firestore.',
        name: 'Promotion.fromFirestore',
        error: 'ID Dokumen Promosi: ${doc.id}',
      );
      price = 0.0; // Ganti NaN dengan nilai aman
    }
    // --- AKHIR DARI PERANGKAP & PENGAMAN ---

    return Promotion(
      id: doc.id,
      productId: data['productId'] ?? '',
      discountPrice: price, // Gunakan harga yang sudah divalidasi
      startDate: (data['startDate'] as Timestamp).toDate(),
      endDate: (data['endDate'] as Timestamp).toDate(),
    );
  }
}

class PromoProduct {
  final Product product;
  final Promotion promotion;

  PromoProduct({
    required this.product,
    required this.promotion,
  });
}
