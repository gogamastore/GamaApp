import 'dart:developer' as developer;
import 'package:cloud_functions/cloud_functions.dart';

// ─────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────

/// Area dari Biteship (untuk autocomplete input kota/kecamatan)
class BiteshipArea {
  final String id;
  final String name;
  final String postalCode;
  final String adminName; // Provinsi, Kabupaten

  const BiteshipArea({
    required this.id,
    required this.name,
    required this.postalCode,
    required this.adminName,
  });

  factory BiteshipArea.fromMap(Map<String, dynamic> map) => BiteshipArea(
        id: map['id'] as String? ?? '',
        name: map['name'] as String? ?? '',
        postalCode: map['postalCode'] as String? ?? '',
        adminName: map['adminName'] as String? ?? '',
      );

  String get displayName => '$name, $adminName ($postalCode)';
}

/// Satu pilihan tarif kurir dari Biteship
class BiteshipRate {
  final String courierId;       // "jnt", "jne", "sicepat", dll
  final String courierName;
  final String courierServiceCode;
  final String serviceName;
  final String description;
  final double price;
  final double originalPrice;
  final double discount;
  final int minDay;
  final int maxDay;
  final String estimatedDelivery;
  final bool available;
  final String? logo;
  final String category; // "same_day" | "next_day" | "reguler" | "cargo"

  const BiteshipRate({
    required this.courierId,
    required this.courierName,
    required this.courierServiceCode,
    required this.serviceName,
    required this.description,
    required this.price,
    required this.originalPrice,
    required this.discount,
    required this.minDay,
    required this.maxDay,
    required this.estimatedDelivery,
    required this.available,
    this.logo,
    required this.category,
  });

  factory BiteshipRate.fromMap(Map<String, dynamic> map) => BiteshipRate(
        courierId: map['courierId'] as String? ?? '',
        courierName: map['courierName'] as String? ?? '',
        courierServiceCode: map['courierServiceCode'] as String? ?? '',
        serviceName: map['serviceName'] as String? ?? '',
        description: map['description'] as String? ?? '',
        price: (map['price'] as num?)?.toDouble() ?? 0,
        originalPrice: (map['originalPrice'] as num?)?.toDouble() ?? 0,
        discount: (map['discount'] as num?)?.toDouble() ?? 0,
        minDay: (map['minDay'] as num?)?.toInt() ?? 1,
        maxDay: (map['maxDay'] as num?)?.toInt() ?? 7,
        estimatedDelivery: map['estimatedDelivery'] as String? ?? '-',
        available: map['available'] as bool? ?? true,
        logo: map['logo'] as String?,
        category: map['category'] as String? ?? 'reguler',
      );

  bool get hasDiscount => discount > 0;

  /// Label kategori untuk tampilan UI
  String get categoryLabel {
    switch (category) {
      case 'same_day':
        return 'Same Day';
      case 'next_day':
        return 'Next Day';
      case 'cargo':
        return 'Cargo';
      default:
        return 'Reguler';
    }
  }
}

/// Item produk yang dikirim (untuk kalkulasi berat & biaya)
class ShipmentItem {
  final String productId;
  final String name;
  final double price;
  final int quantity;
  final int weightGram; // berat per item dalam gram

  const ShipmentItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.quantity,
    required this.weightGram,
  });

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'name': name,
        'price': price,
        'quantity': quantity,
        'weightGram': weightGram,
      };
}

/// Hasil booking order Biteship
class BiteshipOrderResult {
  final bool success;
  final String biteshipOrderId;
  final String waybillId;
  final String status;
  final String trackingUrl;

  const BiteshipOrderResult({
    required this.success,
    required this.biteshipOrderId,
    required this.waybillId,
    required this.status,
    required this.trackingUrl,
  });
}

/// Satu entry di history tracking
class TrackingHistory {
  final String timestamp;
  final String status;
  final String note;

  const TrackingHistory({
    required this.timestamp,
    required this.status,
    required this.note,
  });

  factory TrackingHistory.fromMap(Map<String, dynamic> map) => TrackingHistory(
        timestamp: map['timestamp'] as String? ?? '',
        status: map['status'] as String? ?? '',
        note: map['note'] as String? ?? '',
      );
}

/// Info tracking lengkap
class BiteshipTrackingInfo {
  final bool hasDelivery;
  final String? biteshipOrderId;
  final String? waybillId;
  final String? status;
  final String? courierName;
  final String? driverName;
  final String? driverPhone;
  final String? trackingUrl;
  final List<TrackingHistory> history;

  const BiteshipTrackingInfo({
    required this.hasDelivery,
    this.biteshipOrderId,
    this.waybillId,
    this.status,
    this.courierName,
    this.driverName,
    this.driverPhone,
    this.trackingUrl,
    this.history = const [],
  });

  factory BiteshipTrackingInfo.fromMap(Map<String, dynamic> map) {
    final historyRaw = map['history'] as List<dynamic>? ?? [];
    return BiteshipTrackingInfo(
      hasDelivery: map['hasDelivery'] as bool? ?? false,
      biteshipOrderId: map['biteshipOrderId'] as String?,
      waybillId: map['waybillId'] as String?,
      status: map['status'] as String?,
      courierName: map['courierName'] as String?,
      driverName: map['driverName'] as String?,
      driverPhone: map['driverPhone'] as String?,
      trackingUrl: map['trackingUrl'] as String?,
      history: historyRaw
          .map((h) => TrackingHistory.fromMap(h as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ─────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────
class BiteshipService {
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );

  /// Cari area Biteship (untuk autocomplete input kota/kecamatan).
  Future<List<BiteshipArea>> searchArea(String input) async {
    try {
      final callable = _functions.httpsCallable('searchBiteshipArea');
      final result = await callable.call({'input': input});
      final data = result.data as Map<String, dynamic>;
      final areas = data['areas'] as List<dynamic>? ?? [];
      return areas
          .map((a) => BiteshipArea.fromMap(a as Map<String, dynamic>))
          .toList();
    } on FirebaseFunctionsException catch (e) {
      developer.log('searchArea error', name: 'BiteshipService', error: e.message);
      throw BiteshipException(e.message ?? 'Gagal mencari area.');
    }
  }

  /// Ambil daftar tarif kurir dari Biteship.
  /// [destinationAreaId] didapat dari [searchArea].
  Future<List<BiteshipRate>> getRates({
    required String destinationAreaId,
    required List<ShipmentItem> items,
    List<String>? couriers,
  }) async {
    try {
      final callable = _functions.httpsCallable('getBiteshipRates');
      final result = await callable.call({
        'destinationAreaId': destinationAreaId,
        'items': items.map((i) => i.toMap()).toList(),
        if (couriers != null) 'couriers': couriers,
      });

      final data = result.data as Map<String, dynamic>;
      final rates = data['rates'] as List<dynamic>? ?? [];
      return rates
          .map((r) => BiteshipRate.fromMap(r as Map<String, dynamic>))
          .toList();
    } on FirebaseFunctionsException catch (e) {
      developer.log('getRates error', name: 'BiteshipService', error: e.message);
      throw BiteshipException(e.message ?? 'Gagal mengambil tarif kurir.');
    }
  }

  /// Buat order + request pickup otomatis ke kurir.
  Future<BiteshipOrderResult> createOrder(String orderId) async {
    try {
      final callable = _functions.httpsCallable('createBiteshipOrder');
      final result = await callable.call({'orderId': orderId});
      final data = result.data as Map<String, dynamic>;

      return BiteshipOrderResult(
        success: data['success'] as bool? ?? false,
        biteshipOrderId: data['biteshipOrderId'] as String? ?? '',
        waybillId: data['waybillId'] as String? ?? '',
        status: data['status'] as String? ?? '',
        trackingUrl: data['trackingUrl'] as String? ?? '',
      );
    } on FirebaseFunctionsException catch (e) {
      developer.log('createOrder error', name: 'BiteshipService', error: e.message);
      throw BiteshipException(e.message ?? 'Gagal membuat order pengiriman.');
    }
  }

  /// Cek status tracking berdasarkan orderId internal.
  Future<BiteshipTrackingInfo> trackOrder(String orderId) async {
    try {
      final callable = _functions.httpsCallable('trackBiteshipOrder');
      final result = await callable.call({'orderId': orderId});
      return BiteshipTrackingInfo.fromMap(result.data as Map<String, dynamic>);
    } on FirebaseFunctionsException catch (e) {
      developer.log('trackOrder error', name: 'BiteshipService', error: e.message);
      return const BiteshipTrackingInfo(hasDelivery: false);
    }
  }
}

class BiteshipException implements Exception {
  final String message;
  BiteshipException(this.message);

  @override
  String toString() => 'BiteshipException: $message';
}
