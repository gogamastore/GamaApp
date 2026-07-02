import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

num _toNum(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value;
  if (value is String) return num.tryParse(value) ?? 0;
  return 0;
}

class ProductItem {
  final String image;
  final String name;
  final num price;
  final String productId;
  final int quantity;

  ProductItem({
    required this.image,
    required this.name,
    required this.price,
    required this.productId,
    required this.quantity,
  });

  factory ProductItem.fromMap(Map<String, dynamic> data) {
    return ProductItem(
      image: data['imageUrl'] ?? data['image'] ?? '',
      name: data['name'] ?? 'Unknown Product',
      price: _toNum(data['price']),
      productId: data['productId'] ?? '',
      quantity: _toNum(data['quantity']).toInt(),
    );
  }
}

class Order {
  final String id;
  final String customer;
  final Map<String, dynamic> customerDetails;
  final Timestamp date;
  final String paymentMethod;
  final String? paymentProofUrl;
  final String paymentStatus;
  final List<ProductItem> products;
  final num shippingFee;
  final String shippingMethod;
  final String status;
  final num subtotal;
  final num total;
  final Timestamp? updatedAt;

  // ── Biteship fields ───────────────────────────────────────────
  final String? biteshipOrderId;
  final String? biteshipCourierCode;
  final String? biteshipCourierName;
  final String? biteshipServiceCode;
  final String? biteshipServiceName;
  final String? biteshipStatus;
  final String? waybillId;
  final String? deliveryTrackingUrl;

  // ── Midtrans fields ───────────────────────────────────────────
  final String? midtransToken;
  final String? midtransRedirectUrl;

  Order({
    required this.id,
    required this.customer,
    required this.customerDetails,
    required this.date,
    required this.paymentMethod,
    this.paymentProofUrl,
    required this.paymentStatus,
    required this.products,
    required this.shippingFee,
    required this.shippingMethod,
    required this.status,
    required this.subtotal,
    required this.total,
    this.updatedAt,
    this.biteshipOrderId,
    this.biteshipCourierCode,
    this.biteshipCourierName,
    this.biteshipServiceCode,
    this.biteshipServiceName,
    this.biteshipStatus,
    this.waybillId,
    this.deliveryTrackingUrl,
    this.midtransToken,
    this.midtransRedirectUrl,
  });

  /// True jika pesanan menggunakan kurir Biteship
  bool get hasBiteshipDelivery =>
      biteshipOrderId != null && biteshipOrderId!.isNotEmpty;

  /// True jika bisa dilacak (waybill sudah ada)
  bool get canTrack =>
      hasBiteshipDelivery &&
      (waybillId != null && waybillId!.isNotEmpty ||
          deliveryTrackingUrl != null && deliveryTrackingUrl!.isNotEmpty);

  /// True jika menunggu pembayaran (belum bayar via Midtrans)
  bool get isPendingPayment => paymentStatus.toLowerCase() == 'pending_payment';

  /// True jika sudah lunas
  bool get isPaid =>
      paymentStatus.toLowerCase() == 'paid' ||
      paymentStatus.toLowerCase() == 'settlement';

  int get totalProducts => products.fold(0, (sum, item) => sum + item.quantity);

  /// Waktu aktivitas terakhir (perubahan status) untuk deteksi notifikasi
  /// "belum dilihat". Fallback ke tanggal order bila updatedAt tidak ada.
  Timestamp get activityAt => updatedAt ?? date;

  String get formattedDate =>
      DateFormat('d MMMM yyyy', 'id_ID').format(date.toDate());

  String get formattedTotal {
    final f =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    return f.format(total);
  }

  factory Order.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final productList = (data['products'] as List<dynamic>?) ?? [];

    return Order(
      id: doc.id,
      customer: data['customerDetails']?['name'] ?? data['customer'] ?? 'N/A',
      customerDetails: (data['customerDetails'] as Map<String, dynamic>?) ?? {},
      date: data['date'] is Timestamp
          ? data['date'] as Timestamp
          : Timestamp.now(),
      paymentMethod: data['paymentMethod'] ?? 'N/A',
      paymentProofUrl: data['paymentProofUrl'] as String?,
      paymentStatus: data['paymentStatus'] ?? 'unpaid',
      products: productList
          .map((p) => ProductItem.fromMap(p as Map<String, dynamic>))
          .toList(),
      shippingFee: _toNum(data['shippingFee']),
      shippingMethod: data['shippingMethod'] ?? 'N/A',
      status: data['status'] ?? 'Unknown',
      subtotal: _toNum(data['subtotal']),
      total: _toNum(data['total']),
      updatedAt: data['updatedAt'] is Timestamp ? data['updatedAt'] as Timestamp : null,
      // Biteship
      biteshipOrderId: data['biteshipOrderId'] as String?,
      biteshipCourierCode: data['biteshipCourierCode'] as String?,
      biteshipCourierName: data['biteshipCourierName'] as String?,
      biteshipServiceCode: data['biteshipServiceCode'] as String?,
      biteshipServiceName: data['biteshipServiceName'] as String?,
      biteshipStatus: data['biteshipStatus'] as String?,
      waybillId: data['waybillId'] as String?,
      deliveryTrackingUrl: data['deliveryTrackingUrl'] as String?,
      // Midtrans
      midtransToken: data['midtransToken'] as String?,
      midtransRedirectUrl: data['midtransRedirectUrl'] as String?,
    );
  }
}
