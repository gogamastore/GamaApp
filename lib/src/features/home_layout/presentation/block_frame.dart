import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/app_layout.dart';

/// Pembungkus umum setiap blok beranda: margin, padding vertikal, warna /
/// gambar latar, radius, dan judul seksi ("Lihat Semua").
///
/// Padding horizontal (`style.paddingH`) TIDAK diterapkan di sini — tiap
/// blok menerapkannya sendiri supaya daftar yang di-scroll horizontal tetap
/// bisa bergeser sampai tepi layar.
class BlockFrame extends StatelessWidget {
  final HomeBlock block;
  final Widget child;
  final VoidCallback? onSeeAll;

  const BlockFrame({
    super.key,
    required this.block,
    required this.child,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    final s = block.style;
    final hasBgImage = s.bgImageUrl.isNotEmpty;
    final hasDecoration = s.bgColor != null || hasBgImage;
    final title = block.title.trim();

    return Container(
      margin: EdgeInsets.fromLTRB(s.marginH, s.marginTop, s.marginH, s.marginBottom),
      padding: EdgeInsets.symmetric(vertical: s.paddingV),
      clipBehavior: hasDecoration && s.radius > 0 ? Clip.antiAlias : Clip.none,
      decoration: hasDecoration
          ? BoxDecoration(
              color: s.bgColor,
              borderRadius: BorderRadius.circular(s.radius),
              image: hasBgImage
                  ? DecorationImage(
                      image: CachedNetworkImageProvider(s.bgImageUrl),
                      fit: BoxFit.cover,
                      onError: (_, __) {},
                    )
                  : null,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title.isNotEmpty || (block.showSeeAll && onSeeAll != null))
            Padding(
              padding: EdgeInsets.fromLTRB(s.paddingH, 0, s.paddingH, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: s.titleColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (block.showSeeAll && onSeeAll != null)
                    TextButton(
                      onPressed: onSeeAll,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: const Text('Lihat Semua'),
                    ),
                ],
              ),
            ),
          child,
        ],
      ),
    );
  }
}

/// URL halaman "Lihat Semua" untuk sumber produk tertentu.
String collectionLink({
  required String source,
  String category = '',
  String brandId = '',
  String title = '',
}) {
  return Uri(path: '/collection', queryParameters: {
    'source': source,
    if (category.isNotEmpty) 'category': category,
    if (brandId.isNotEmpty) 'brandId': brandId,
    if (title.isNotEmpty) 'title': title,
  }).toString();
}

/// Ubah link yang diisi admin menjadi rute aplikasi. Link web reseller
/// (mis. `/reseller/products/ID`) ikut diterjemahkan supaya banner yang sama
/// bisa dipakai di web & aplikasi. Mengembalikan null bila tidak dikenali.
String? resolveAppLink(String link) {
  final l = link.trim();
  if (l.isEmpty) return null;
  if (l.startsWith('http://') || l.startsWith('https://')) return l;

  final uri = Uri.tryParse(l);
  if (uri == null) return null;
  final seg = uri.pathSegments;

  if (seg.isNotEmpty && seg.first == 'reseller') {
    if (seg.length >= 3 && seg[1] == 'products') return '/product/${seg[2]}';
    if (seg.length >= 3 && seg[1] == 'brands') {
      return collectionLink(source: 'brand', brandId: seg[2], title: 'Brand');
    }
    if (seg.length >= 2 && seg[1] == 'promo') {
      return collectionLink(source: 'promo', title: 'Promo');
    }
    if (seg.length >= 2 && seg[1] == 'trending') {
      return collectionLink(source: 'trending', title: 'Produk Trending');
    }
    if (seg.length >= 2 && seg[1] == 'cart') return '/cart';
    return '/catalog';
  }

  const known = [
    '/', '/catalog', '/notifications', '/profile', '/cart', '/chat',
    '/collection', '/product/', '/profile/',
  ];
  final path = uri.path;
  final ok = known.any((k) => k.endsWith('/') && k != '/' ? path.startsWith(k) : path == k);
  return ok ? l : null;
}

/// Buka link dari konfigurasi blok/banner.
Future<void> openAppLink(BuildContext context, String link) async {
  final target = resolveAppLink(link);
  if (target == null) return;

  if (target.startsWith('http')) {
    await launchUrl(Uri.parse(target), mode: LaunchMode.externalApplication);
    return;
  }
  if (!context.mounted) return;

  // Rute tab utama memakai go (pindah tab), sisanya push (bisa kembali).
  const tabRoots = {'/', '/catalog', '/notifications', '/profile'};
  if (tabRoots.contains(Uri.parse(target).path)) {
    context.go(target);
  } else {
    context.push(target);
  }
}
