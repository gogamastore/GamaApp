import 'package:cloud_firestore/cloud_firestore.dart';

/// Voucher belanja yang dikelola admin (koleksi `vouchers`) dan dipakai di
/// checkout reseller.
class Voucher {
  final String id;
  final String code;
  final String description;
  final String discountType; // 'fixed' | 'percentage'
  final num discountValue;
  final num maxDiscount; // cap % (0 = tanpa batas)
  final num minPurchase;
  final DateTime? startDate;
  final DateTime? endDate;
  final int dailyLimitPerUser; // 0 = tanpa batas
  final String limitType; // 'perDay' (per 24 jam) | 'perEvent' (seluruh event)

  const Voucher({
    required this.id,
    required this.code,
    this.description = '',
    this.discountType = 'fixed',
    this.discountValue = 0,
    this.maxDiscount = 0,
    this.minPurchase = 0,
    this.startDate,
    this.endDate,
    this.dailyLimitPerUser = 0,
    this.limitType = 'perDay',
  });

  bool get isPerEvent => limitType == 'perEvent';

  factory Voucher.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    DateTime? toDate(dynamic v) => v is Timestamp ? v.toDate() : null;
    return Voucher(
      id: doc.id,
      code: (data['code'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      discountType:
          data['discountType'] == 'percentage' ? 'percentage' : 'fixed',
      discountValue: (data['discountValue'] as num?) ?? 0,
      maxDiscount: (data['maxDiscount'] as num?) ?? 0,
      minPurchase: (data['minPurchase'] as num?) ?? 0,
      startDate: toDate(data['startDate']),
      endDate: toDate(data['endDate']),
      dailyLimitPerUser: (data['dailyLimitPerUser'] as num?)?.toInt() ?? 0,
      limitType: data['limitType'] == 'perEvent' ? 'perEvent' : 'perDay',
    );
  }

  /// Masih dalam masa berlaku (tanggal)?
  bool get isDateValid {
    final now = DateTime.now();
    if (startDate != null && now.isBefore(startDate!)) return false;
    if (endDate != null && now.isAfter(endDate!)) return false;
    return true;
  }
}
