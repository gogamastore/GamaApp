import 'package:cloud_firestore/cloud_firestore.dart';

/// Ulasan pembeli untuk satu produk pada satu pesanan. Dokumen disimpan di
/// koleksi `reviews` dengan id = "{orderId}_{productId}" agar tidak ganda.
class Review {
  final String id;
  final String productId;
  final String orderId;
  final String userId;
  final String userName;
  final bool anonymous;
  final int rating; // 1..5
  final String comment;
  final List<String> imageUrls;
  final Timestamp? createdAt;

  Review({
    required this.id,
    required this.productId,
    required this.orderId,
    required this.userId,
    required this.userName,
    required this.anonymous,
    required this.rating,
    required this.comment,
    this.imageUrls = const [],
    this.createdAt,
  });

  /// Nama yang ditampilkan — disamarkan bila pembeli memilih sembunyikan nama.
  String get displayName {
    if (!anonymous) return userName.isEmpty ? 'Pengguna' : userName;
    final n = userName.trim();
    if (n.isEmpty) return 'Pengguna';
    if (n.length <= 2) return '${n[0]}***';
    return '${n.substring(0, 2)}***${n.substring(n.length - 1)}';
  }

  factory Review.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Review(
      id: doc.id,
      productId: data['productId'] as String? ?? '',
      orderId: data['orderId'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      userName: data['userName'] as String? ?? '',
      anonymous: data['anonymous'] as bool? ?? false,
      rating: (data['rating'] as num? ?? 0).toInt().clamp(0, 5),
      comment: data['comment'] as String? ?? '',
      imageUrls: (data['imageUrls'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList(),
      createdAt: data['createdAt'] as Timestamp?,
    );
  }
}

/// Satu baris isian ulasan (sebelum dikirim) untuk sebuah produk di pesanan.
class ReviewDraft {
  final String productId;
  final String productName;
  final String productImage;
  int rating;
  String comment;
  List<String> imageUrls;

  ReviewDraft({
    required this.productId,
    required this.productName,
    required this.productImage,
    this.rating = 5,
    this.comment = '',
    this.imageUrls = const [],
  });
}
