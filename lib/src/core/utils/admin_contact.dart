import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// Kontak WhatsApp admin (koleksi Firestore: whatsapp_contacts) + pembangun
/// pesan untuk fitur "Hubungi" (obrolan aplikasi & WhatsApp).

final _rp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

class AdminContact {
  final String name;
  final String whatsapp;
  const AdminContact({required this.name, required this.whatsapp});
}

/// Ambil kontak WhatsApp admin pertama (urut createdAt) dari whatsapp_contacts.
Future<AdminContact?> fetchAdminContact() async {
  final snap = await FirebaseFirestore.instance
      .collection('whatsapp_contacts')
      .orderBy('createdAt')
      .limit(1)
      .get();
  if (snap.docs.isEmpty) return null;
  final d = snap.docs.first.data();
  final wa = (d['whatsapp'] ?? '').toString();
  if (wa.isEmpty) return null;
  return AdminContact(name: (d['name'] ?? 'Admin').toString(), whatsapp: wa);
}

/// Buka WhatsApp admin dengan pesan terisi otomatis. Return false bila gagal.
Future<bool> openAdminWhatsapp(String whatsapp, String text) async {
  final digits = whatsapp.replaceAll(RegExp(r'[^0-9]'), '');
  final uri =
      Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(text)}');
  if (await canLaunchUrl(uri)) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
  return false;
}

String _shortId(String id) =>
    id.length >= 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase();

/// Pesan riwayat pesanan untuk dikirim ke obrolan aplikasi (chat internal).
String orderChatMessage({
  required String id,
  required num total,
  required String statusLabel,
  required List<String> productLines,
}) {
  return 'Halo admin, saya ingin bertanya tentang pesanan berikut:\n\n'
      '🧾 Pesanan #${_shortId(id)}\n'
      'Status: $statusLabel\n'
      'Total: ${_rp.format(total)}\n\n'
      'Produk:\n${productLines.join('\n')}';
}

/// Pesan pesanan untuk WhatsApp admin (nomor pesanan + hal yang ditanyakan).
String orderWhatsappMessage({
  required String id,
  required num total,
  required String statusLabel,
  required String adminName,
}) {
  return 'Halo $adminName, saya ingin bertanya tentang pesanan saya.\n\n'
      'Nomor Pesanan: #${_shortId(id)}\n'
      'Total: ${_rp.format(total)}\n'
      'Status: $statusLabel\n\n'
      'Yang ingin saya tanyakan: ';
}

/// Pesan produk (nama + harga + link) untuk dikirim ke obrolan aplikasi.
String productChatMessage({
  required String name,
  required double price,
  required String link,
}) {
  return 'Halo admin, saya ingin bertanya tentang produk ini:\n\n'
      '🛍️ $name\n'
      '💰 ${_rp.format(price)}\n'
      '🔗 $link';
}
