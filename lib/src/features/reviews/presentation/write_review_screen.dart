import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/data/firestore_service.dart';
import '../../authentication/data/auth_service.dart';
import '../../orders/domain/order.dart';
import '../domain/review.dart';

/// Halaman "Beri Ulasan": menampilkan semua produk dari satu pesanan, lalu
/// pembeli memberi bintang + komentar (+ foto opsional) untuk tiap produk.
class WriteReviewScreen extends StatefulWidget {
  final Order order;
  const WriteReviewScreen({super.key, required this.order});

  @override
  State<WriteReviewScreen> createState() => _WriteReviewScreenState();
}

class _ReviewRow {
  final ReviewDraft draft;
  final List<XFile> photos = [];
  _ReviewRow(this.draft);
}

class _WriteReviewScreenState extends State<WriteReviewScreen> {
  late final List<_ReviewRow> _rows;
  bool _anonymous = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // Dedupe produk berdasarkan productId (id dokumen ulasan = orderId_productId).
    final seen = <String>{};
    _rows = [
      for (final p in widget.order.products)
        if (p.productId.isNotEmpty && seen.add(p.productId))
          _ReviewRow(ReviewDraft(
            productId: p.productId,
            productName: p.name,
            productImage: p.image,
          )),
    ];
  }

  Future<void> _pickPhotos(_ReviewRow row) async {
    final picked = await ImagePicker().pickMultiImage(imageQuality: 70);
    if (picked.isEmpty) return;
    setState(() {
      row.photos.addAll(picked);
      if (row.photos.length > 5) row.photos.removeRange(5, row.photos.length);
    });
  }

  Future<void> _submit() async {
    final auth = context.read<AuthService>();
    final firestore = context.read<FirestoreService>();
    final user = auth.currentUser;
    if (user == null) return;

    final rated = _rows.where((r) => r.draft.rating > 0).toList();
    if (rated.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Beri minimal 1 bintang pada salah satu produk.')),
      );
      return;
    }

    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      // Unggah foto (bila ada) lalu isi imageUrls tiap draft.
      for (final r in rated) {
        if (r.photos.isEmpty) continue;
        final urls = <String>[];
        for (final f in r.photos) {
          urls.add(await firestore.uploadReviewPhoto(user.uid, f));
        }
        r.draft.imageUrls = urls;
      }

      await firestore.submitOrderReviews(
        orderId: widget.order.id,
        userId: user.uid,
        userName: user.name.isEmpty ? widget.order.customer : user.name,
        anonymous: _anonymous,
        drafts: rated.map((r) => r.draft).toList(),
      );

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Terima kasih! Ulasan berhasil dikirim.')),
      );
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(SnackBar(content: Text('Gagal mengirim ulasan: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Beri Ulasan')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final row in _rows) _buildProductReview(row),
          CheckboxListTile(
            value: _anonymous,
            onChanged: (v) => setState(() => _anonymous = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('Sembunyikan nama saya pada ulasan'),
          ),
          const SizedBox(height: 80),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton(
            onPressed: _submitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _submitting
                ? const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Kirim Ulasan'),
          ),
        ),
      ),
    );
  }

  Widget _buildProductReview(_ReviewRow row) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header produk
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: row.draft.productImage.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: row.draft.productImage,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) =>
                                Container(color: Colors.grey[200], child: const Icon(Icons.image_not_supported, size: 20)),
                          )
                        : Container(color: Colors.grey[200], child: const Icon(Icons.image, size: 20)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(row.draft.productName,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Bintang
            Row(
              children: List.generate(5, (i) {
                final filled = i < row.draft.rating;
                return IconButton(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => row.draft.rating = i + 1),
                  icon: Icon(filled ? Icons.star : Icons.star_border,
                      color: const Color(0xFFFBBF24), size: 32),
                );
              }),
            ),
            const SizedBox(height: 8),
            // Komentar
            TextField(
              minLines: 2,
              maxLines: 4,
              onChanged: (v) => row.draft.comment = v,
              decoration: InputDecoration(
                hintText: 'Tulis ulasanmu tentang produk ini (opsional)...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            // Foto
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...row.photos.asMap().entries.map((e) => Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          // Image.file tidak didukung di Flutter web; di web
                          // XFile.path berupa blob URL yang bisa dibaca
                          // Image.network.
                          child: kIsWeb
                              ? Image.network(
                                  e.value.path,
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _localThumb(e.value),
                                )
                              : Image.file(
                                  File(e.value.path),
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _localThumb(e.value),
                                ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: GestureDetector(
                            onTap: () => setState(() => row.photos.removeAt(e.key)),
                            child: Container(
                              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                              child: const Icon(Icons.close, size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    )),
                if (row.photos.length < 5)
                  InkWell(
                    onTap: () => _pickPhotos(row),
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo_outlined, size: 20, color: Colors.grey[600]),
                          const SizedBox(height: 2),
                          Text('Foto', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Thumbnail file lokal (Image.network path gagal di Android → pakai FileImage
  // via Image.asset tak cocok; cukup placeholder kecil sebelum diunggah).
  Widget _localThumb(XFile file) =>
      Container(width: 64, height: 64, color: Colors.grey[200], child: const Icon(Icons.image, size: 20));
}
