import 'dart:developer' as developer;
import 'package:cloud_functions/cloud_functions.dart';

class BiteshipArea {
  final String id;
  final String name;
  final String postalCode;
  final String adminName;

  const BiteshipArea({
    required this.id,
    required this.name,
    required this.postalCode,
    required this.adminName,
  });

  factory BiteshipArea.fromMap(Map<String, dynamic> map) => BiteshipArea(
        id: map['id'] as String? ?? '',
        name: map['name'] as String? ?? '',
        postalCode: map['postalCode']?.toString() ?? '',
        adminName: map['adminName'] as String? ?? '',
      );

  String get displayName => '$name ($postalCode)';
}

class BiteshipRate {
  final String courierId;
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
  final String category;

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

  String get categoryLabel {
    switch (category) {
      case 'same_day': return 'Instan';
      case 'next_day': return 'Next Day';
      case 'cargo': return 'Cargo';
      default: return 'Reguler';
    }
  }
}

class ShipmentItem {
  final String productId;
  final String name;
  final double price;
  final int quantity;
  final int weightGram;

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

class BiteshipService {
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );

  Future<List<BiteshipArea>> searchArea(String input) async {
    try {
      final callable = _functions.httpsCallable('searchBiteshipArea');
      final result = await callable.call({'input': input});
      final data = result.data as Map<String, dynamic>;
      final areas = data['areas'] as List<dynamic>? ?? [];
      developer.log('searchArea "$input": ${areas.length} hasil',
          name: 'BiteshipService');
      return areas
          .map((a) => BiteshipArea.fromMap(a as Map<String, dynamic>))
          .toList();
    } on FirebaseFunctionsException catch (e) {
      developer.log('searchArea error',
          name: 'BiteshipService', error: '${e.code}: ${e.message}');
      throw BiteshipException(e.message ?? 'Gagal mencari area.');
    } catch (e) {
      developer.log('searchArea unexpected error',
          name: 'BiteshipService', error: e);
      throw BiteshipException('Gagal mencari area: $e');
    }
  }

  // ── KUNCI: getRates dengan koordinat GPS destination ──────────
  // destinationLatitude & destinationLongitude WAJIB dikirim agar
  // kurir instan (GoSend, Grab, Paxel) muncul di hasil rates.
  Future<List<BiteshipRate>> getRates({
    required String destinationAreaId,
    required List<ShipmentItem> items,
    List<String>? couriers,
    double? destinationLatitude,
    double? destinationLongitude,
  }) async {
    try {
      final callable = _functions.httpsCallable('getBiteshipRates');

      final payload = <String, dynamic>{
        'destinationAreaId': destinationAreaId,
        'items': items.map((i) => i.toMap()).toList(),
        if (couriers != null) 'couriers': couriers,
        if (destinationLatitude != null)
          'destinationLatitude': destinationLatitude,
        if (destinationLongitude != null)
          'destinationLongitude': destinationLongitude,
      };

      developer.log(
        'getRates: area=$destinationAreaId, '
        'hasCoords=${destinationLatitude != null}, '
        'items=${items.length}',
        name: 'BiteshipService',
      );

      final result = await callable.call(payload);
      final data = result.data as Map<String, dynamic>;
      final rates = data['rates'] as List<dynamic>? ?? [];

      developer.log('getRates: ${rates.length} layanan tersedia',
          name: 'BiteshipService');

      return rates
          .map((r) => BiteshipRate.fromMap(r as Map<String, dynamic>))
          .toList();
    } on FirebaseFunctionsException catch (e) {
      developer.log('getRates error',
          name: 'BiteshipService', error: '${e.code}: ${e.message}');
      throw BiteshipException(e.message ?? 'Gagal mengambil tarif kurir.');
    } catch (e) {
      developer.log('getRates unexpected error',
          name: 'BiteshipService', error: e);
      throw BiteshipException('Gagal mengambil tarif: $e');
    }
  }

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
      throw BiteshipException(e.message ?? 'Gagal membuat order.');
    }
  }

  Future<BiteshipTrackingInfo> trackOrder(String orderId) async {
    try {
      final callable = _functions.httpsCallable('trackBiteshipOrder');
      final result = await callable.call({'orderId': orderId});
      return BiteshipTrackingInfo.fromMap(
          result.data as Map<String, dynamic>);
    } on FirebaseFunctionsException catch (_) {
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
