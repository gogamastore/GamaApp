import 'package:cloud_firestore/cloud_firestore.dart';

class Product {
  final String id;
  final String name;
  final String description;
  final double price;
  final String imageUrl;
  final String category;
  final int stock;
  final int weightGram;
  final String sku;
  final Timestamp? purchaseAt; // waktu terakhir dibeli/restock (untuk urutan katalog)

  Product({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.imageUrl,
    required this.category,
    required this.stock,
    this.weightGram = 0,
    this.sku = '',
    this.purchaseAt,
  });

  // --- LOGIKA BARU DIMULAI DI SINI ---
  Product copyWith({
    String? id,
    String? name,
    String? description,
    double? price,
    String? imageUrl,
    String? category,
    int? stock,
    int? weightGram,
    String? sku,
    Timestamp? purchaseAt,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      imageUrl: imageUrl ?? this.imageUrl,
      category: category ?? this.category,
      stock: stock ?? this.stock,
      weightGram: weightGram ?? this.weightGram,
      sku: sku ?? this.sku,
      purchaseAt: purchaseAt ?? this.purchaseAt,
    );
  }
  // --- LOGIKA BARU BERAKHIR DI SINI ---

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'image': imageUrl,
      'category': category,
      'stock': stock,
      'weightGram': weightGram,
      'sku': sku,
    };
  }

  /// Parse harga dari Firestore yang bisa berupa NUMBER (double/int) ATAU
  /// STRING. Web admin menyimpan harga produk sebagai string — baik angka
  /// polos ("150000") maupun terformat ("Rp 150.000"). Karena format Rupiah
  /// memakai titik sebagai pemisah RIBUAN (tanpa desimal), semua karakter
  /// non-digit dibuang lalu di-parse. Aman untuk num maupun string kosong.
  static double parsePrice(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      return double.tryParse(digits) ?? 0.0;
    }
    return 0.0;
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Nama Tidak Diketahui',
      description: map['description'] as String? ?? '',
      price: parsePrice(map['price']),
      imageUrl: map['image'] as String? ?? '',
      category: map['category'] as String? ?? 'Lain-lain',
      stock: (map['stock'] as num? ?? 0).toInt(),
      weightGram: (map['weightGram'] as num? ?? 0).toInt(),
      // SKU/barcode bisa tersimpan sebagai int (mis. 8992821100422) ATAU
      // string di Firestore, jadi konversi apa pun ke String agar tidak error.
      sku: map['sku']?.toString() ?? '',
      purchaseAt: map['purchaseAt'] as Timestamp?,
    );
  }

  factory Product.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    data['id'] = doc.id;
    return Product.fromMap(data);
  }
}
