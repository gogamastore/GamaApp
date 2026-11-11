import 'package:flutter/material.dart';

import '../utils/admin_contact.dart';

/// Bottom sheet "Hubungi Admin" bersama: opsi Obrolan (opsional) + DAFTAR semua
/// kontak WhatsApp dari koleksi whatsapp_contacts (tiap kontak = satu pilihan,
/// menampilkan NAMA kontak sesuai yang admin tambahkan).
///
/// [onChat] = aksi "Obrolan" (chat aplikasi); bila null, opsi Obrolan disembunyikan.
/// [buildWhatsappMessage] = pesan WhatsApp sesuai konteks (nama admin diisi dari
/// kontak terpilih).
Future<void> showAdminContactSheet(
  BuildContext context, {
  VoidCallback? onChat,
  required String Function(String adminName) buildWhatsappMessage,
}) async {
  final contacts = await fetchAdminContacts();
  if (!context.mounted) return;

  await showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Hubungi Admin',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
          ),
          if (onChat != null)
            ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.1),
                child: Icon(Icons.chat_bubble_outline,
                    color: Theme.of(ctx).colorScheme.primary),
              ),
              title: const Text('Obrolan'),
              subtitle: const Text('Chat di aplikasi'),
              onTap: () {
                Navigator.pop(ctx);
                onChat();
              },
            ),
          if (contacts.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Belum ada kontak WhatsApp admin.',
                    style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in contacts)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.green.withValues(alpha: 0.12),
                        child: const Icon(Icons.chat, color: Colors.green),
                      ),
                      title: Text(c.name),
                      subtitle: const Text('WhatsApp'),
                      onTap: () async {
                        Navigator.pop(ctx);
                        final ok = await openAdminWhatsapp(
                            c.whatsapp, buildWhatsappMessage(c.name));
                        if (!ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Tidak dapat membuka WhatsApp.')),
                          );
                        }
                      },
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
