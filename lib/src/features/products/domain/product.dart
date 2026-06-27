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

  factory Product.fromMap(Map<String, dynamic> map) {
    double parsedPrice = 0.0;
    final priceValue = map['price'];

    if (priceValue is num) {
      parsedPrice = priceValue.toDouble();
    } else if (priceValue is String) {
      try {
        final cleanString = priceValue.replaceAll(RegExp(r'[^0-9]'), '');
        parsedPrice = double.tryParse(cleanString) ?? 0.0;
      } catch (_) {
        parsedPrice = 0.0;
      }
    }

    return Product(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Nama Tidak Diketahui',
      description: map['description'] as String? ?? '',
      price: parsedPrice,
      imageUrl: map['image'] as String? ?? '',
      category: map['category'] as String? ?? 'Lain-lain',
      stock: (map['stock'] as num? ?? 0).toInt(),
      weightGram: (map['weightGram'] as num? ?? 0).toInt(),
      sku: map['sku'] as String? ?? '',
    );
  }

  factory Product.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    data['id'] = doc.id;
    return Product.fromMap(data);
  }
}
