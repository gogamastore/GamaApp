import 'dart:developer' as developer;
import 'package:cloud_functions/cloud_functions.dart';

// ─────────────────────────────────────────────
// Helper: konversi Map<Object?, Object?> → Map<String, dynamic>
// Wajib di Android karena Firebase Functions mengembalikan tipe Java Map
// yang tidak kompatibel langsung dengan Map<String, dynamic> Dart
// ─────────────────────────────────────────────
Map<String, dynamic> _toStringDynamic(Object? obj) {
  if (obj is Map<String, dynamic>) return obj;
  if (obj is Map) {
    return obj.map((k, v) {
      final key = k?.toString() ?? '';
      final value = v is Map
          ? _toStringDynamic(v)
          : v is List
              ? _toListDynamic(v)
              : v;
      return MapEntry(key, value);
    });
  }
  return {};
}

List<dynamic> _toListDynamic(List obj) {
  return obj.map((item) {
    if (item is Map) return _toStringDynamic(item);
    if (item is List) return _toListDynamic(item);
    return item;
  }).toList();
}

// ─────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────

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
        id: map['id']?.toString() ?? '',
        name: map['name']?.toString() ?? '',
        postalCode: map['postalCode']?.toString() ?? '',
        adminName: map['adminName']?.toString() ?? '',
      );

  String get displayName => '$name, $adminName ($postalCode)';
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
        courierId: map['courierId']?.toString() ?? '',
        courierName: map['courierName']?.toString() ?? '',
        courierServiceCode: map['courierServiceCode']?.toString() ?? '',
        serviceName: map['serviceName']?.toString() ?? '',
        description: map['description']?.toString() ?? '',
        price: (map['price'] as num?)?.toDouble() ?? 0,
        originalPrice: (map['originalPrice'] as num?)?.toDouble() ?? 0,
        discount: (map['discount'] as num?)?.toDouble() ?? 0,
        minDay: (map['minDay'] as num?)?.toInt() ?? 1,
        maxDay: (map['maxDay'] as num?)?.toInt() ?? 7,
        estimatedDelivery: map['estimatedDelivery']?.toString() ?? '-',
        available: map['available'] as bool? ?? true,
        logo: map['logo']?.toString(),
        category: map['category']?.toString() ?? 'reguler',
      );

  bool get hasDiscount => discount > 0;

  String get categoryLabel {
    switch (category) {
      case 'same_day':
        return 'Instan';
      case 'next_day':
        return 'Next Day';
      case 'cargo':
        return 'Cargo';
      default:
        return 'Reguler';
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
        timestamp: map['timestamp']?.toString() ?? '',
        status: map['status']?.toString() ?? '',
        note: map['note']?.toString() ?? '',
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
      biteshipOrderId: map['biteshipOrderId']?.toString(),
      waybillId: map['waybillId']?.toString(),
      status: map['status']?.toString(),
      courierName: map['courierName']?.toString(),
      driverName: map['driverName']?.toString(),
      driverPhone: map['driverPhone']?.toString(),
      trackingUrl: map['trackingUrl']?.toString(),
      history: historyRaw
          .map((h) => TrackingHistory.fromMap(_toStringDynamic(h)))
          .toList(),
    );
  }
}

// ─────────────────────────────────────────────
// Exception
// ─────────────────────────────────────────────

class BiteshipException implements Exception {
  final String message;
  final String? code;
  BiteshipException(this.message, {this.code});

  @override
  String toString() => 'BiteshipException[$code]: $message';
}

// ─────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────

class BiteshipService {
  // Region HARUS cocok dengan deployment Cloud Function
  // Beda region → Android silent fail, Chrome tidak terpengaruh
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );

  // 30 detik — akomodasi cold start Cloud Function di Android (5-10 detik)
  static const _timeout = Duration(seconds: 30);

  /// Cari area Biteship (autocomplete input kecamatan/kode pos)
  Future<List<BiteshipArea>> searchArea(String input) async {
    developer.log('searchArea START: "$input"', name: 'BiteshipService');
    try {
      final callable = _functions.httpsCallable(
        'searchBiteshipArea',
        options: HttpsCallableOptions(timeout: _timeout),
      );
      final result = await callable.call({'input': input});

      // ── FIX: konversi Map<Object?, Object?> → Map<String, dynamic> ──
      final data = _toStringDynamic(result.data);
      final areasRaw = data['areas'] as List<dynamic>? ?? [];

      developer.log('searchArea "$input": ${areasRaw.length} hasil',
          name: 'BiteshipService');

      return areasRaw
          .map((a) => BiteshipArea.fromMap(_toStringDynamic(a)))
          .toList();
    } on FirebaseFunctionsException catch (e) {
      developer.log(
          'searchArea FIREBASE ERROR: code=${e.code} msg=${e.message}',
          name: 'BiteshipService');
      throw BiteshipException(e.message ?? 'Gagal mencari area.', code: e.code);
    } catch (e, st) {
      developer.log('searchArea UNEXPECTED: $e',
          name: 'BiteshipService', stackTrace: st);
      throw BiteshipException('Gagal mencari area: $e');
    }
  }

  /// Ambil tarif kurir Biteship (reguler + instan via Mix Rates).
  ///
  /// [destinationAreaId] — wajib.
  /// [destinationLatitude] & [destinationLongitude] — opsional,
  /// tapi DIPERLUKAN agar GoSend/Grab/Paxel ikut muncul.
  Future<List<BiteshipRate>> getRates({
    required String destinationAreaId,
    required List<ShipmentItem> items,
    List<String>? couriers,
    double? destinationLatitude,
    double? destinationLongitude,
  }) async {
    final hasCoords =
        destinationLatitude != null && destinationLongitude != null;
    developer.log(
      'getRates START: area=$destinationAreaId, items=${items.length}, hasCoords=$hasCoords',
      name: 'BiteshipService',
    );

    try {
      final callable = _functions.httpsCallable(
        'getBiteshipRates',
        options: HttpsCallableOptions(timeout: _timeout),
      );

      final payload = <String, dynamic>{
        'destinationAreaId': destinationAreaId,
        'items': items.map((i) => i.toMap()).toList(),
        if (couriers != null) 'couriers': couriers,
        if (destinationLatitude != null)
          'destinationLatitude': destinationLatitude,
        if (destinationLongitude != null)
          'destinationLongitude': destinationLongitude,
      };

      developer.log('getRates payload: $payload', name: 'BiteshipService');

      final result = await callable.call(payload);

      developer.log(
        'getRates raw result type: ${result.data.runtimeType}',
        name: 'BiteshipService',
      );

      // ── FIX UTAMA: konversi Map<Object?, Object?> → Map<String, dynamic> ──
      // Di Android, Firebase Functions mengembalikan Map<Object?, Object?>
      // karena Java reflection. Di Chrome/web mengembalikan Map<String, dynamic>.
      // _toStringDynamic() menyelesaikan perbedaan ini secara rekursif.
      final data = _toStringDynamic(result.data);
      final ratesRaw = data['rates'] as List<dynamic>? ?? [];

      developer.log('getRates SUCCESS: ${ratesRaw.length} layanan',
          name: 'BiteshipService');

      return ratesRaw
          .map((r) => BiteshipRate.fromMap(_toStringDynamic(r)))
          .toList();
    } on FirebaseFunctionsException catch (e) {
      developer.log(
        'getRates FIREBASE ERROR: code=${e.code}, msg=${e.message}, details=${e.details}',
        name: 'BiteshipService',
      );
      throw BiteshipException(e.message ?? 'Gagal mengambil tarif kurir.',
          code: e.code);
    } catch (e, st) {
      developer.log('getRates UNEXPECTED: $e',
          name: 'BiteshipService', stackTrace: st);
      throw BiteshipException('Gagal mengambil tarif: $e');
    }
  }

  Future<BiteshipOrderResult> createOrder(String orderId) async {
    try {
      final callable = _functions.httpsCallable(
        'createBiteshipOrder',
        options: HttpsCallableOptions(timeout: _timeout),
      );
      final result = await callable.call({'orderId': orderId});
      // ── FIX: konversi sebelum parse ──
      final data = _toStringDynamic(result.data);
      return BiteshipOrderResult(
        success: data['success'] as bool? ?? false,
        biteshipOrderId: data['biteshipOrderId']?.toString() ?? '',
        waybillId: data['waybillId']?.toString() ?? '',
        status: data['status']?.toString() ?? '',
        trackingUrl: data['trackingUrl']?.toString() ?? '',
      );
    } on FirebaseFunctionsException catch (e) {
      developer.log('createOrder FIREBASE ERROR: code=${e.code}',
          name: 'BiteshipService');
      throw BiteshipException(e.message ?? 'Gagal membuat order.',
          code: e.code);
    } catch (e, st) {
      developer.log('createOrder UNEXPECTED: $e',
          name: 'BiteshipService', stackTrace: st);
      throw BiteshipException('Gagal membuat order: $e');
    }
  }

  Future<BiteshipTrackingInfo> trackOrder(String orderId) async {
    try {
      final callable = _functions.httpsCallable(
        'trackBiteshipOrder',
        options: HttpsCallableOptions(timeout: _timeout),
      );
      final result = await callable.call({'orderId': orderId});
      // ── FIX: konversi sebelum parse ──
      return BiteshipTrackingInfo.fromMap(_toStringDynamic(result.data));
    } on FirebaseFunctionsException catch (e) {
      developer.log('trackOrder FIREBASE ERROR: code=${e.code}',
          name: 'BiteshipService');
      return const BiteshipTrackingInfo(hasDelivery: false);
    } catch (e) {
      developer.log('trackOrder UNEXPECTED: $e', name: 'BiteshipService');
      return const BiteshipTrackingInfo(hasDelivery: false);
    }
  }
}
