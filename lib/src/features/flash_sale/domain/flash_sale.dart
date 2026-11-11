import 'package:cloud_firestore/cloud_firestore.dart';

import '../../products/domain/product.dart';

/// Status event flash sale pada suatu waktu.
enum FlashSaleStatus { upcoming, teaser, active, ended }

/// Satu produk dalam event flash sale beserta harga flash-nya.
class FlashSaleItem {
  final String productId;
  final double flashPrice;

  const FlashSaleItem({required this.productId, required this.flashPrice});
}

/// Event flash sale (koleksi `flash_sales`). Skema mengikuti web
/// `Gallery-POS-Web/src/lib/flash-sale.ts`.
class FlashSale {
  final String id;
  final String title;
  final DateTime startAt;
  final DateTime endAt;

  /// Teaser muncul sejak (startAt - cooldownMinutes).
  final int cooldownMinutes;
  final List<FlashSaleItem> products;

  /// true = pembeli hanya boleh checkout 1 produk & 1 pcs dari event ini.
  final bool oneItemPerEvent;

  /// Batas pcs per produk (null = tak dibatasi khusus).
  final int? maxQtyPerBuyer;

  const FlashSale({
    required this.id,
    required this.title,
    required this.startAt,
    required this.endAt,
    required this.cooldownMinutes,
    required this.products,
    required this.oneItemPerEvent,
    required this.maxQtyPerBuyer,
  });

  DateTime get teaserStart =>
      startAt.subtract(Duration(minutes: cooldownMinutes));

  FlashSaleStatus statusAt(DateTime now) {
    if (!now.isBefore(endAt)) return FlashSaleStatus.ended; // now >= endAt
    if (!now.isBefore(startAt)) return FlashSaleStatus.active; // start<=now<end
    if (!now.isBefore(teaserStart)) return FlashSaleStatus.teaser;
    return FlashSaleStatus.upcoming;
  }

  Set<String> get productIds => products.map((e) => e.productId).toSet();

  /// Harga flash untuk sebuah produk, atau null bila produk bukan bagian event.
  double? flashPriceFor(String productId) {
    for (final p in products) {
      if (p.productId == productId) return p.flashPrice;
    }
    return null;
  }

  static DateTime _toDate(dynamic v, DateTime fallback) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return fallback;
  }

  factory FlashSale.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>? ?? {});
    final now = DateTime.now();
    final rawProducts = data['products'];
    final items = <FlashSaleItem>[];
    if (rawProducts is List) {
      for (final p in rawProducts) {
        if (p is! Map) continue;
        final id = (p['productId'] ?? '').toString();
        if (id.isEmpty) continue;
        items.add(FlashSaleItem(
          productId: id,
          flashPrice: Product.parsePrice(p['flashPrice']),
        ));
      }
    }
    return FlashSale(
      id: doc.id,
      title: (data['title'] ?? 'Flash Sale').toString(),
      startAt: _toDate(data['startAt'], now),
      endAt: _toDate(data['endAt'], now),
      cooldownMinutes: (data['cooldownMinutes'] as num?)?.toInt() ?? 0,
      products: items,
      oneItemPerEvent: data['oneItemPerEvent'] == true,
      maxQtyPerBuyer: (data['maxQtyPerBuyer'] as num?)?.toInt(),
    );
  }
}

/// Sensor harga untuk kartu teaser: hanya angka PERTAMA yang terlihat.
/// Contoh: 15000 → "Rp 1••••".
String censorFlashPrice(double price) {
  final value = price < 0 ? 0 : price.round();
  final digits = value.toString();
  if (digits == '0') return 'Rp ?';
  final first = digits[0];
  final masked = '•' * (digits.length - 1);
  return 'Rp $first$masked';
}
