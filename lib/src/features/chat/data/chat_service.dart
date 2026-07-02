import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../domain/chat_message.dart';

/// Layanan chat pembeli ↔ admin. Satu thread per pengguna: chats/{userId}.
class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Stream<List<ChatMessage>> messagesStream(String userId) {
    return _db
        .collection('chats')
        .doc(userId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => ChatMessage.fromFirestore(d)).toList());
  }

  /// Jumlah pesan belum dibaca dari admin (untuk badge).
  Stream<int> unreadStream(String userId) {
    return _db.collection('chats').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return 0;
      final data = doc.data() as Map<String, dynamic>;
      return (data['unreadForUser'] as num? ?? 0).toInt();
    });
  }

  Future<String> uploadImage(String userId, File file) async {
    final ref = _storage
        .ref()
        .child('chat_images')
        .child(userId)
        .child('${DateTime.now().millisecondsSinceEpoch}.jpg');
    await ref.putFile(file);
    return ref.getDownloadURL();
  }

  Future<void> sendMessage({
    required String userId,
    required String senderId,
    required String senderRole,
    required String text,
    String? imageUrl,
    String? userName,
    String? userEmail,
    String? userPhotoURL,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && imageUrl == null) return;

    final threadRef = _db.collection('chats').doc(userId);

    await threadRef.collection('messages').add({
      'senderId': senderId,
      'senderRole': senderRole,
      'text': trimmed,
      if (imageUrl != null) 'imageUrl': imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final preview =
        trimmed.isNotEmpty ? trimmed : (imageUrl != null ? '📷 Foto' : '');

    await threadRef.set({
      'userId': userId,
      if (userName != null && userName.isNotEmpty) 'userName': userName,
      if (userEmail != null && userEmail.isNotEmpty) 'userEmail': userEmail,
      if (userPhotoURL != null && userPhotoURL.isNotEmpty)
        'userPhotoURL': userPhotoURL,
      'lastMessage': preview,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastSenderRole': senderRole,
      'unreadForAdmin':
          senderRole == 'user' ? FieldValue.increment(1) : FieldValue.increment(0),
      'unreadForUser':
          senderRole == 'admin' ? FieldValue.increment(1) : FieldValue.increment(0),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> markRead(String userId, String role) async {
    final field = role == 'admin' ? 'unreadForAdmin' : 'unreadForUser';
    await _db
        .collection('chats')
        .doc(userId)
        .set({field: 0}, SetOptions(merge: true));
  }
}
