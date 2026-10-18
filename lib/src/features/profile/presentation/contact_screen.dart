import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Satu entri kontak (dikelola admin dari web dashboard → "Contact Profil").
class _ContactItem {
  final String section;
  final String type;
  final String label;
  final String url;
  const _ContactItem({
    required this.section,
    required this.type,
    required this.label,
    required this.url,
  });
}

/// Default — sama dengan kontak lama, dipakai sebagai fallback bila admin
/// belum mengonfigurasi dokumen settings/contact_profile.
const List<_ContactItem> _defaultContacts = [
  _ContactItem(section: 'Akun Official Kami', type: 'instagram', label: 'manafidh_kosmetik', url: 'https://www.instagram.com/manafidh_kosmetik/'),
  _ContactItem(section: 'Akun Official Kami', type: 'website', label: 'www.gogama.store', url: 'https://www.gogama.store/'),
  _ContactItem(section: 'Akun Official Kami', type: 'tiktok', label: 'Gallery Makassar', url: 'https://www.tiktok.com/@gallery.makassar'),
  _ContactItem(section: 'Akun Official Kami', type: 'shopee', label: 'manafidh_kosmetik', url: 'https://shope.ee/6Kbmbbr5pA'),
  _ContactItem(section: 'Hubungi Kami Untuk Join Grosir', type: 'whatsapp', label: 'WA Komplain Shopee', url: 'http://wa.me/6289506991107'),
  _ContactItem(section: 'Hubungi Kami Untuk Join Grosir', type: 'whatsapp', label: 'Admin Grosir 1', url: 'http://wa.me/6288705707321'),
  _ContactItem(section: 'Hubungi Kami Untuk Join Grosir', type: 'whatsapp', label: 'Admin Grosir 2', url: 'http://wa.me/6289503674236'),
  _ContactItem(section: 'Hubungi Kami Untuk Join Grosir', type: 'whatsapp', label: 'WA Lowongan Kerja', url: 'http://wa.me/6289636052501'),
  _ContactItem(section: 'Offline Store', type: 'maps', label: 'Maps: Gallery Makassar', url: 'https://maps.app.goo.gl/BQmTCJBcVRaeU7wi9'),
];

FaIconData _iconForType(String type) {
  switch (type) {
    case 'whatsapp':
      return FontAwesomeIcons.whatsapp;
    case 'instagram':
      return FontAwesomeIcons.instagram;
    case 'tiktok':
      return FontAwesomeIcons.tiktok;
    case 'facebook':
      return FontAwesomeIcons.facebook;
    case 'youtube':
      return FontAwesomeIcons.youtube;
    case 'website':
      return FontAwesomeIcons.globe;
    case 'shopee':
      return FontAwesomeIcons.bagShopping;
    case 'maps':
      return FontAwesomeIcons.mapLocationDot;
    case 'email':
      return FontAwesomeIcons.envelope;
    case 'phone':
      return FontAwesomeIcons.phone;
    default:
      return FontAwesomeIcons.globe;
  }
}

class ContactScreen extends StatelessWidget {
  const ContactScreen({super.key});

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // throw 'Could not launch $url';
    }
  }

  List<_ContactItem> _parse(Map<String, dynamic>? data) {
    final raw = (data?['items'] as List?) ?? const [];
    final items = raw.whereType<Map>().map((m) {
      return _ContactItem(
        section: (m['section'] as String?)?.trim() ?? '',
        type: (m['type'] as String?)?.trim() ?? 'website',
        label: (m['label'] as String?)?.trim() ?? '',
        url: (m['url'] as String?)?.trim() ?? '',
      );
    }).where((i) => i.label.isNotEmpty && i.url.isNotEmpty).toList();
    return items.isNotEmpty ? items : _defaultContacts;
  }

  @override
  Widget build(BuildContext context) {
    final docRef =
        FirebaseFirestore.instance.collection('settings').doc('contact_profile');

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Hubungi Kami',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF075664), Color(0xFF2aadc4)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: docRef.snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              }

              final items = _parse(snapshot.data?.data());

              // Kelompokkan per section dengan mempertahankan urutan.
              final groups = <String, List<_ContactItem>>{};
              for (final it in items) {
                final name = it.section.isEmpty ? 'Kontak' : it.section;
                groups.putIfAbsent(name, () => []).add(it);
              }

              final children = <Widget>[];
              groups.forEach((section, tiles) {
                children.add(_buildSectionHeader(section));
                for (final t in tiles) {
                  children.add(ContactInfoTile(
                    icon: _iconForType(t.type),
                    text: t.label,
                    onTap: () => _launchURL(t.url),
                  ));
                }
                children.add(const SizedBox(height: 10));
              });

              return ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                children: children,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0, bottom: 15, top: 15),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}

class ContactInfoTile extends StatelessWidget {
  final FaIconData icon;
  final String text;
  final VoidCallback onTap;

  const ContactInfoTile({
    super.key,
    required this.icon,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shadowColor: Colors.black45,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 18),
          child: Row(
            children: [
              FaIcon(icon, size: 24, color: const Color(0xFF075664)),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF211B21),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
