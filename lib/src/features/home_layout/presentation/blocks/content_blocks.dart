import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/data/firestore_service.dart';
import '../../../products/domain/banner_item.dart';
import '../../../products/domain/brand.dart';
import '../../../products/presentation/parent_subcategories_screen.dart';
import '../../../products/presentation/widgets/banner_carousel.dart';
import '../../domain/app_layout.dart';
import '../block_frame.dart';

EdgeInsets _horizontal(HomeBlock block) =>
    EdgeInsets.symmetric(horizontal: block.style.paddingH);

TextAlign _textAlign(String value) => switch (value) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.left,
    };

// ─── Banner ──────────────────────────────────────────────────────────────

class BannerBlockView extends StatefulWidget {
  final HomeBlock block;

  const BannerBlockView({super.key, required this.block});

  @override
  State<BannerBlockView> createState() => _BannerBlockViewState();
}

class _BannerBlockViewState extends State<BannerBlockView> {
  late final Stream<List<BannerItem>> _stream =
      context.read<FirestoreService>().getBannersStream();

  @override
  Widget build(BuildContext context) {
    final c = widget.block.config;
    final height = c.number('height', 200).clamp(80, 400).toDouble();

    return StreamBuilder<List<BannerItem>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();
        if (!snapshot.hasData) {
          return SizedBox(
            height: height,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        final banners = snapshot.data!;
        if (banners.isEmpty) return const SizedBox.shrink();
        return BlockFrame(
          block: widget.block,
          child: Padding(
            padding: _horizontal(widget.block),
            child: BannerCarousel(
              banners: banners,
              height: height,
              viewportFraction: c.number('viewportFraction', 1.0).clamp(0.5, 1.0).toDouble(),
              itemMarginH: c.number('itemMarginH', 8),
              radius: c.number('radius', 15),
              autoplaySeconds: c.integer('autoplaySeconds', 6),
              showIndicator: c.boolean('showIndicator', true),
              showText: c.boolean('showText', true),
              onTap: (banner) => openAppLink(context, banner.link),
            ),
          ),
        );
      },
    );
  }
}

// ─── Brand ───────────────────────────────────────────────────────────────

class BrandsBlockView extends StatefulWidget {
  final HomeBlock block;

  const BrandsBlockView({super.key, required this.block});

  @override
  State<BrandsBlockView> createState() => _BrandsBlockViewState();
}

class _BrandsBlockViewState extends State<BrandsBlockView> {
  late final Stream<List<Brand>> _stream =
      context.read<FirestoreService>().getBrandsStream();

  void _open(Brand brand) {
    if (brand.id.isEmpty) return;
    context.push(collectionLink(source: 'brand', brandId: brand.id, title: brand.name));
  }

  Widget _logo(Brand brand, double size) {
    // Brand tanpa logo (mis. dibuat cepat dari form produk) → ikon, bukan
    // Image.network('') yang memicu error.
    if (brand.logoUrl.isEmpty) {
      return Icon(Icons.business, color: Colors.grey, size: size * 0.4);
    }
    return Image.network(
      brand.logoUrl,
      fit: BoxFit.contain,
      // Tangani gagal muat (offline/DNS/404) agar tidak bocor ke
      // Crashlytics sebagai error fatal.
      errorBuilder: (context, error, stackTrace) =>
          Icon(Icons.business, color: Colors.grey, size: size * 0.4),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.block.config;
    final isCircle = c.string('style', 'card') == 'circle';
    final size = c.number('itemSize', 70).clamp(40, 140).toDouble();
    final titleColor = widget.block.style.titleColor;

    return StreamBuilder<List<Brand>>(
      stream: _stream,
      builder: (context, snapshot) {
        final brands = snapshot.data ?? const <Brand>[];
        if (snapshot.hasError || (snapshot.hasData && brands.isEmpty)) {
          return const SizedBox.shrink();
        }
        if (!snapshot.hasData) return SizedBox(height: size);

        final list = ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: _horizontal(widget.block),
          itemCount: brands.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final brand = brands[index];
            if (isCircle) {
              return SizedBox(
                width: size + 12,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _open(brand),
                  child: Column(
                    children: [
                      Container(
                        width: size,
                        height: size,
                        padding: EdgeInsets.all(size * 0.15),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipOval(child: _logo(brand, size)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        brand.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: titleColor),
                      ),
                    ],
                  ),
                ),
              );
            }
            return SizedBox(
              width: size * 100 / 70,
              child: Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _open(brand),
                  child: Column(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: _logo(brand, size),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                        child: Text(
                          brand.name,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: titleColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );

        return BlockFrame(
          block: widget.block,
          onSeeAll: () => context.push('/brands'),
          child: SizedBox(height: isCircle ? size + 24 : size, child: list),
        );
      },
    );
  }
}

// ─── Kategori ────────────────────────────────────────────────────────────

class CategoriesBlockView extends StatefulWidget {
  final HomeBlock block;

  const CategoriesBlockView({super.key, required this.block});

  @override
  State<CategoriesBlockView> createState() => _CategoriesBlockViewState();
}

class _CategoriesBlockViewState extends State<CategoriesBlockView> {
  late final Stream<List<String>> _stream =
      context.read<FirestoreService>().getCategoryNamesStream();

  void _open(String name) =>
      context.push(collectionLink(source: 'category', category: name, title: name));

  /// Avatar huruf awal (fallback bila kartu gambar belum punya gambar).
  Widget _letter(String name, Color color, double size) => Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Text(
          (name.isEmpty ? '?' : name).characters.first.toUpperCase(),
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: size * 0.4),
        ),
      );

  /// Gaya "Gambar (geser)": kartu manual dari config.items (nama + gambar +
  /// kategori tujuan). Tidak membaca daftar kategori otomatis.
  Widget _buildImageSlider(BuildContext context, ConfigMap c, Color color) {
    const maxItems = 8;
    final limit = c.integer('limit', maxItems).clamp(1, maxItems);
    final size = c.number('itemSize', 84).clamp(56, 140).toDouble();
    final items = c.list('items').take(limit).where((it) {
      return it.string('name', '').isNotEmpty || it.string('imageUrl', '').isNotEmpty;
    }).toList();
    if (items.isEmpty) return const SizedBox.shrink();

    return BlockFrame(
      block: widget.block,
      onSeeAll: () => context.push('/categories'),
      child: SizedBox(
        height: size + 28,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: _horizontal(widget.block),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final it = items[i];
            final name = it.string('name', '');
            final img = it.string('imageUrl', '');
            final category = it.string('category', '');
            return SizedBox(
              width: size + 14,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: category.isEmpty
                    ? null
                    : () => context.push(collectionLink(
                          source: 'category',
                          category: category,
                          title: name.isEmpty ? category : name,
                        )),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: size,
                      height: size,
                      child: img.isEmpty
                          ? _letter(name, color, size)
                          : CachedNetworkImage(
                              imageUrl: img,
                              fit: BoxFit.contain,
                              errorWidget: (context, url, error) => _letter(name, color, size),
                            ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, height: 1.2, color: widget.block.style.titleColor),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _circle(String name, Color color, double size) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _open(name),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              name.characters.first.toUpperCase(),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: size * 0.4,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, height: 1.2, color: widget.block.style.titleColor),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.block.config;
    final style = c.string('style', 'chip');
    final color = Theme.of(context).colorScheme.primary;

    // Gaya gambar manual tidak membaca daftar kategori otomatis.
    if (style == 'imageSlider') {
      return _buildImageSlider(context, c, color);
    }

    final columns = c.integer('columns', 4).clamp(2, 6);
    final limit = c.integer('limit', 12).clamp(1, 50);

    return StreamBuilder<List<String>>(
      stream: _stream,
      builder: (context, snapshot) {
        final names = (snapshot.data ?? const <String>[]).take(limit).toList();
        if (names.isEmpty) return const SizedBox.shrink();

        Widget child;
        if (style == 'grid') {
          final rows = <Widget>[];
          for (var i = 0; i < names.length; i += columns) {
            if (rows.isNotEmpty) rows.add(const SizedBox(height: 12));
            rows.add(Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var k = 0; k < columns; k++)
                  Expanded(
                    child: i + k < names.length
                        ? _circle(names[i + k], color, 48)
                        : const SizedBox.shrink(),
                  ),
              ],
            ));
          }
          child = Padding(padding: _horizontal(widget.block), child: Column(children: rows));
        } else if (style == 'circle') {
          child = SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: _horizontal(widget.block),
              itemCount: names.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) =>
                  SizedBox(width: 68, child: _circle(names[i], color, 52)),
            ),
          );
        } else {
          child = SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: _horizontal(widget.block),
              itemCount: names.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) => Material(
                color: Colors.white,
                shape: StadiumBorder(
                  side: BorderSide(color: color.withValues(alpha: 0.35)),
                ),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => _open(names[i]),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Center(
                      child: Text(
                        names[i],
                        style: TextStyle(
                          fontSize: 13,
                          color: widget.block.style.titleColor ?? color,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        return BlockFrame(
          block: widget.block,
          onSeeAll: () => context.push('/categories'),
          child: child,
        );
      },
    );
  }
}

// ─── Induk Kategori ────────────────────────────────────────────────────────

class ParentCategoriesBlockView extends StatefulWidget {
  final HomeBlock block;

  const ParentCategoriesBlockView({super.key, required this.block});

  @override
  State<ParentCategoriesBlockView> createState() =>
      _ParentCategoriesBlockViewState();
}

class _ParentCategoriesBlockViewState extends State<ParentCategoriesBlockView> {
  late final Stream<List<({String id, String name, String imageUrl})>> _stream =
      context.read<FirestoreService>().getParentCategoriesStream();

  void _open(({String id, String name, String imageUrl}) p) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          ParentSubcategoriesScreen(parentId: p.id, parentName: p.name),
    ));
  }

  Widget _avatar(({String id, String name, String imageUrl}) p, Color color, double size) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _open(p),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: p.imageUrl.isNotEmpty
                ? Image.network(
                    p.imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stack) => Text(
                      p.name.characters.first.toUpperCase(),
                      style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: size * 0.4),
                    ),
                  )
                : Text(
                    p.name.characters.first.toUpperCase(),
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: size * 0.4),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            p.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, height: 1.2, color: widget.block.style.titleColor),
          ),
        ],
      ),
    );
  }

  /// Kartu gaya "image" — gambar PNG datar (tanpa lingkaran), digeser.
  Widget _imageCard(({String id, String name, String imageUrl}) p, Color color, double size) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _open(p),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: p.imageUrl.isNotEmpty
                ? Image.network(
                    p.imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stack) => _letterBox(p, color, size),
                  )
                : _letterBox(p, color, size),
          ),
          const SizedBox(height: 6),
          Text(
            p.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, height: 1.2, color: widget.block.style.titleColor),
          ),
        ],
      ),
    );
  }

  Widget _letterBox(({String id, String name, String imageUrl}) p, Color color, double size) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
      child: Text(
        p.name.characters.first.toUpperCase(),
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: size * 0.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.block.config;
    final style = c.string('style', 'circle');
    final columns = c.integer('columns', 4).clamp(2, 6);
    final limit = c.integer('limit', 12).clamp(1, 50);
    final itemSize = c.integer('itemSize', 64).clamp(36, 140).toDouble();
    final order = c.stringList('order');
    final color = Theme.of(context).colorScheme.primary;

    return StreamBuilder<List<({String id, String name, String imageUrl})>>(
      stream: _stream,
      builder: (context, snapshot) {
        final parents =
            orderByIds(snapshot.data ?? const [], (p) => p.id, order).take(limit).toList();
        if (parents.isEmpty) return const SizedBox.shrink();

        Widget child;
        if (style == 'grid') {
          final rows = <Widget>[];
          for (var i = 0; i < parents.length; i += columns) {
            if (rows.isNotEmpty) rows.add(const SizedBox(height: 12));
            rows.add(Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var k = 0; k < columns; k++)
                  Expanded(
                    child: i + k < parents.length
                        ? _avatar(parents[i + k], color, 48)
                        : const SizedBox.shrink(),
                  ),
              ],
            ));
          }
          child = Padding(padding: _horizontal(widget.block), child: Column(children: rows));
        } else if (style == 'image') {
          child = SizedBox(
            height: itemSize + 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: _horizontal(widget.block),
              itemCount: parents.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) =>
                  SizedBox(width: itemSize + 14, child: _imageCard(parents[i], color, itemSize)),
            ),
          );
        } else if (style == 'chip') {
          child = SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: _horizontal(widget.block),
              itemCount: parents.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) => Material(
                color: Colors.white,
                shape: StadiumBorder(side: BorderSide(color: color.withValues(alpha: 0.35))),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => _open(parents[i]),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Center(
                      child: Text(parents[i].name,
                          style: TextStyle(fontSize: 13, color: widget.block.style.titleColor ?? color, fontWeight: FontWeight.w500)),
                    ),
                  ),
                ),
              ),
            ),
          );
        } else {
          child = SizedBox(
            height: itemSize + 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: _horizontal(widget.block),
              itemCount: parents.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) =>
                  SizedBox(width: itemSize + 16, child: _avatar(parents[i], color, itemSize)),
            ),
          );
        }
        return BlockFrame(block: widget.block, child: child);
      },
    );
  }
}

// ─── Kotak pencarian ─────────────────────────────────────────────────────

class SearchBlockView extends StatelessWidget {
  final HomeBlock block;

  const SearchBlockView({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    final c = block.config;
    final radius = BorderRadius.circular(c.number('radius', 10));
    return BlockFrame(
      block: block,
      child: Padding(
        padding: _horizontal(block),
        child: Material(
          color: c.color('bgColor', Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: c.color('borderColor', const Color(0xFFE5E7EB))!),
          ),
          child: InkWell(
            borderRadius: radius,
            // Katalog sudah punya kolom pencarian sendiri.
            onTap: () => context.go('/catalog'),
            child: SizedBox(
              height: 44,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(Icons.search, size: 20, color: Colors.grey[500]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      c.string('placeholder', 'Cari produk...'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey[500], fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Teks ────────────────────────────────────────────────────────────────

class TextBlockView extends StatelessWidget {
  final HomeBlock block;

  const TextBlockView({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    final c = block.config;
    final text = c.string('text', '').trim();
    if (text.isEmpty && block.title.trim().isEmpty) return const SizedBox.shrink();
    return BlockFrame(
      block: block,
      child: text.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: _horizontal(block),
              child: Text(
                text,
                textAlign: _textAlign(c.string('align', 'left')),
                style: TextStyle(
                  fontSize: c.number('fontSize', 16).clamp(8, 48).toDouble(),
                  fontWeight: c.boolean('bold', true) ? FontWeight.bold : FontWeight.normal,
                  color: c.color('color', const Color(0xFF1F2937)),
                ),
              ),
            ),
    );
  }
}

// ─── Gambar ──────────────────────────────────────────────────────────────

class ImageBlockView extends StatelessWidget {
  final HomeBlock block;

  const ImageBlockView({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    final c = block.config;
    final url = c.string('imageUrl', '').trim();
    if (url.isEmpty) return const SizedBox.shrink();
    final link = c.string('link', '');
    final radius = BorderRadius.circular(c.number('radius', 12));
    // Tinggi tetap (px) seperti banner bila > 0; selain itu ikut rasio.
    final height = c.number('height', 0).toDouble();
    // Lebar penuh halaman → tanpa padding samping (full-bleed seperti banner).
    final fullWidth = c.boolean('fullWidth', false);

    final image = CachedNetworkImage(
      imageUrl: url,
      fit: c.string('fit', 'cover') == 'contain' ? BoxFit.contain : BoxFit.cover,
      placeholder: (context, url) => ColoredBox(color: Colors.grey.shade200),
      errorWidget: (context, url, error) => ColoredBox(
        color: Colors.grey.shade200,
        child: const Icon(Icons.broken_image, color: Colors.grey),
      ),
    );
    final sized = height > 0
        ? SizedBox(height: height, width: double.infinity, child: image)
        : AspectRatio(
            aspectRatio: c.number('aspectRatio', 2).clamp(0.3, 5).toDouble(),
            child: image,
          );

    return BlockFrame(
      block: block,
      child: Padding(
        padding: fullWidth ? EdgeInsets.zero : _horizontal(block),
        child: ClipRRect(
          borderRadius: radius,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: link.trim().isEmpty ? null : () => openAppLink(context, link),
              child: sized,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Jarak / garis pemisah ───────────────────────────────────────────────

class SpacerBlockView extends StatelessWidget {
  final HomeBlock block;

  const SpacerBlockView({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    final c = block.config;
    final height = c.number('height', 16).clamp(0, 200).toDouble();
    return BlockFrame(
      block: block,
      child: c.boolean('showDivider', false)
          ? Padding(
              padding: _horizontal(block),
              child: Divider(
                height: height,
                thickness: 1,
                color: c.color('dividerColor', const Color(0xFFE5E7EB)),
              ),
            )
          : SizedBox(height: height),
    );
  }
}

// ─── Tombol ──────────────────────────────────────────────────────────────

class ButtonBlockView extends StatelessWidget {
  final HomeBlock block;

  const ButtonBlockView({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    final c = block.config;
    final label = c.string('label', 'Lihat Semua Produk');
    final link = c.string('link', '/catalog');
    final color = c.color('color');
    final outlined = c.string('style', 'filled') == 'outlined';
    final showIcon = c.boolean('showIcon', true);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(c.number('radius', 10)),
    );
    final size = Size(double.infinity, c.number('height', 50).clamp(32, 80).toDouble());
    const textStyle = TextStyle(fontSize: 16, fontWeight: FontWeight.bold);
    void onPressed() => openAppLink(context, link);

    final Widget button;
    if (outlined) {
      final style = OutlinedButton.styleFrom(
        minimumSize: size,
        textStyle: textStyle,
        shape: shape,
        foregroundColor: color,
        side: color == null ? null : BorderSide(color: color),
      );
      button = showIcon
          ? OutlinedButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.storefront),
              label: Text(label),
              style: style,
            )
          : OutlinedButton(onPressed: onPressed, style: style, child: Text(label));
    } else {
      final style = ElevatedButton.styleFrom(
        minimumSize: size,
        textStyle: textStyle,
        shape: shape,
        backgroundColor: color,
      );
      button = showIcon
          ? ElevatedButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.storefront),
              label: Text(label),
              style: style,
            )
          : ElevatedButton(onPressed: onPressed, style: style, child: Text(label));
    }

    return BlockFrame(
      block: block,
      child: Padding(padding: _horizontal(block), child: button),
    );
  }
}
