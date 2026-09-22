import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String name;
  final String email;
  final String photoURL;
  final String role;
  final String whatsapp;

  /// Status verifikasi nomor WhatsApp: 'verified' atau 'unverified'.
  /// Akun lama yang belum punya field ini dianggap 'unverified' sehingga
  /// tetap diminta memverifikasi nomornya sebelum memesan.
  final String whatsappStatus;

  AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.photoURL,
    required this.role,
    required this.whatsapp,
    required this.whatsappStatus,
  });

  bool get isWhatsappVerified => whatsappStatus == 'verified';

  // Factory constructor to create an AppUser from a Firestore document.
  factory AppUser.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};
    // Field kanonik 'whatsappStatus'; ejaan 'WhatsappStatus' ikut dibaca agar
    // dokumen yang dibuat manual lewat Firebase Console tetap dikenali.
    final rawStatus = data['whatsappStatus'] ?? data['WhatsappStatus'];
    return AppUser(
      uid: doc.id,
      name: data['name'] ?? 'Nama Tidak Ditemukan',
      email: data['email'] ?? 'Email Tidak Ditemukan',
      photoURL: data['photoURL'] ?? '',
      role: data['role'] ?? 'user',
      whatsapp: data['whatsapp'] ?? 'Nomor Tidak Ditemukan',
      whatsappStatus: rawStatus == 'verified' ? 'verified' : 'unverified',
    );
  }
}
