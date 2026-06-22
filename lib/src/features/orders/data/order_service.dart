import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:firebase_storage/firebase_storage.dart';
import '../domain/order.dart';
import 'dart:developer' as developer;

class OrderService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<Order> getOrderById(String orderId) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('orders').doc(orderId).get();
      return Order.fromFirestore(doc);
    } catch (e, s) {
      developer.log('Error getting order by ID', name: 'myapp.order_service', error: e, stackTrace: s);
      rethrow;
    }
  }

  Future<String> uploadPaymentProof({
    required String userId,
    required String orderId,
    required Uint8List imageBytes,
  }) async {
    try {
      String fileName = 'payment_proofs/${userId}_${orderId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      Reference storageRef = _storage.ref().child(fileName);

      UploadTask uploadTask = storageRef.putData(imageBytes, SettableMetadata(contentType: 'image/jpeg'));
      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();

      // ONLY update the proof URL and timestamp. DO NOT change the payment status.
      await _firestore.collection('orders').doc(orderId).update({
        'paymentProofUrl': downloadUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return downloadUrl;
    } catch (e, s) {
      developer.log('Error uploading payment proof', name: 'myapp.order_service', error: e, stackTrace: s);
      rethrow;
    }
  }
}