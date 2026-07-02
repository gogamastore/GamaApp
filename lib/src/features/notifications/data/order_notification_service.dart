import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:rxdart/rxdart.dart';

import '../../orders/domain/order.dart';

/// Layanan notifikasi berbasis pesanan pembeli (tanpa FCM).
/// - Feed status pesanan realtime.
/// - Badge "belum dilihat": jumlah pesanan yang berubah setelah terakhir dilihat.
class OrderNotificationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<Order>> ordersStream(String uid) {
    return _db
        .collection('orders')
        .where('customerId', isEqualTo: uid)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Order.fromFirestore(d)).toList());
  }

  Stream<Timestamp?> _lastSeenStream(String uid) {
    return _db.collection('user').doc(uid).snapshots().map(
          (doc) => doc.data()?['notificationsLastSeenAt'] as Timestamp?,
        );
  }

  /// Jumlah pesanan dengan aktivitas setelah `notificationsLastSeenAt`.
  Stream<int> unseenCountStream(String uid) {
    return Rx.combineLatest2<List<Order>, Timestamp?, int>(
      ordersStream(uid),
      _lastSeenStream(uid),
      (orders, lastSeen) {
        final seenAt = lastSeen?.toDate();
        if (seenAt == null) return orders.length;
        return orders
            .where((o) => o.activityAt.toDate().isAfter(seenAt))
            .length;
      },
    );
  }

  /// Tandai semua notifikasi sudah dilihat (dipanggil saat tab dibuka).
  Future<void> markSeen(String uid) {
    return _db.collection('user').doc(uid).set(
      {'notificationsLastSeenAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }
}
