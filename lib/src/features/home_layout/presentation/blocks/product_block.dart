import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/data/firestore_service.dart';
import '../../../products/domain/product.dart';
import '../../domain/app_layout.dart';
import '../block_frame.dart';
import '../widgets/configurable_product_card.dart';

/// Lebar minimum kartu sebelum memakai teks ringkas. Harus sama dengan
/// `COMPACT_CARD_WIDTH` di preview web.
const double _compactCardWidth = 120;

/// Urutkan, saring stok, lalu potong sesuai konfigurasi blok.
List<Product> prepareProducts(List<Product> items, ProductBlockConfig config) {
  final list = config.hideOutOfStock
      ? items.where((p) => p.stock > 0).toList()
      : List<Product>.of(items);
  switch (config.sort) {
    case 'priceAsc':
      list.sort((a, b) => a.price.compareTo(b.price));
    case 'priceDesc':
      list.sort((a, b) => b.price.compareTo(a.price));
    case 'nameAsc':
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    case 'stockDesc':
      list.sort((a, b) => b.stock.compareTo(a.stock));
  }
  return list.take(config.limit).toList();
}

/// Blok "Produk" di beranda — sumber data & tampilan diatur dari App Builder.
class ProductBlockView extends StatefulWidget {
  final HomeBlock block;

  const ProductBlockView({super.key, required this.block});

  @override
  State<ProductBlockView> createState() => _ProductBlockViewState();
}

class _ProductBlockViewState extends State<ProductBlockView> {
  late ProductBlockConfig _config;
  Stream<List<Product>>? _stream;
  String _queryKey = '';

  @override
  void initState() {
    super.initState();
    _config = ProductBlockConfig.fromConfig(widget.block.config);
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant ProductBlockView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _config = ProductBlockConfig.fromConfig(widget.block.config);
    // Stream hanya dibuat ulang bila query berubah, bukan saat admin hanya
    // mengganti tampilan kartu.
    if (_config.queryKey != _queryKey) _subscribe();
  }

  void _subscribe() {
    _queryKey = _config.queryKey;
    // Ambil lebih banyak bila produk habis disembunyikan, agar setelah
    // disaring jumlahnya tetap mendekati limit.
    final fetchLimit = _config.hideOutOfStock ? _config.limit * 3 : _config.limit;
    _stream = context.read<FirestoreService>().getProductsForSource(
          source: _config.source,
          category: _config.category,
          brandId: _config.brandId,
          limit: fetchLimit,
        );
  }

  void _openSeeAll() {
    context.push(collectionLink(
      source: _config.source,
      category: _config.category,
      brandId: _config.brandId,
      title: widget.block.title.trim().isEmpty ? 'Produk' : widget.block.title.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Product>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          developer.log('Gagal memuat produk blok ${widget.block.id}',
              name: 'ProductBlockView', error: snapshot.error);
          return const SizedBox.shrink();
        }
        if (!snapshot.hasData) {
          return BlockFrame(
            block: widget.block,
            child: const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final products = prepareProducts(snapshot.data!, _config);
        // Sama seperti seksi Flash Sale lama: sembunyikan bila kosong.
        if (products.isEmpty) return const SizedBox.shrink();

        return BlockFrame(
          block: widget.block,
          onSeeAll: _openSeeAll,
          child: LayoutBuilder(
            builder: (context, constraints) => ProductLayoutView(
              products: products,
              config: _config,
              paddingH: widget.block.style.paddingH,
              fullWidth: constraints.maxWidth,
            ),
          ),
        );
      },
    );
  }
}

/// Merender daftar produk sesuai `config.layout`.
class ProductLayoutView extends StatelessWidget {
  final List<Product> products;
  final ProductBlockConfig config;
  final double paddingH;
  final double fullWidth;

  const ProductLayoutView({
    super.key,
    required this.products,
    required this.config,
    required this.paddingH,
    required this.fullWidth,
  });

  ProductCardStyle get _style => config.card;
  double get _spacing => config.spacing;
  double get _innerWidth => math.max(fullWidth - paddingH * 2, 100);

  @override
  Widget build(BuildContext context) {
    switch (config.layout) {
      case ProductLayout.threeColumn:
        return _horizontal(_columnWidth(3), config.rows);
      case ProductLayout.fourColumn:
        return _horizontal(_columnWidth(4), config.rows);
      case ProductLayout.largeCard:
        return _horizontal((fullWidth - paddingH) * 0.8, 1);
      case ProductLayout.grid:
        return _grid();
      case ProductLayout.staggered:
        return _staggered();
      case ProductLayout.listTile:
        return _listTile();
      case ProductLayout.simpleList:
        return _simpleList();
      case ProductLayout.carousel:
        return _ProductCarousel(products: products, config: config, fullWidth: fullWidth);
      case ProductLayout.quilted:
        return _quilted();
      case ProductLayout.twoColumn:
      default:
        return _horizontal(_columnWidth(2), config.rows);
    }
  }

  /// Lebar kartu agar [cols] kartu penuh + 20% kartu berikutnya terlihat.
  double _columnWidth(int cols) =>
      math.max((fullWidth - paddingH - _spacing * cols) / (cols + 0.2), 60);

  /// Ruang ekstra atas/bawah agar bayangan kartu tidak terpotong oleh area
  /// scroll horizontal.
  double get _shadowPad => _style.shadowEnabled
      ? (_style.shadowBlur / 2 + _style.shadowOffsetY.abs()).clamp(0, 20).toDouble()
      : 0;

  Widget _card(Product product, double width, {bool fill = true, double? ratio}) {
    return ConfigurableProductCard(
      product: product,
      style: _style,
      compact: width < _compactCardWidth,
      fillHeight: fill,
      imageRatio: ratio,
    );
  }

  Widget _horizontal(double itemWidth, int requestedRows) {
    final rows = math.max(1, math.min(requestedRows, products.length));
    final columns = (products.length / rows).ceil();

    Widget rowAt(int r) {
      final children = <Widget>[];
      for (var j = 0; j < columns; j++) {
        final index = j * rows + r;
        if (j > 0) children.add(SizedBox(width: _spacing));
        children.add(SizedBox(
          width: itemWidth,
          child: index < products.length
              ? _card(products[index], itemWidth)
              : const SizedBox.shrink(),
        ));
      }
      return IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: _shadowPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var r = 0; r < rows; r++) ...[
            if (r > 0) SizedBox(height: _spacing),
            rowAt(r),
          ],
        ],
      ),
    );
  }

  Widget _grid() {
    final cols = config.gridColumns;
    final itemWidth = (_innerWidth - _spacing * (cols - 1)) / cols;
    final rows = <Widget>[];
    for (var i = 0; i < products.length; i += cols) {
      if (rows.isNotEmpty) rows.add(SizedBox(height: _spacing));
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var k = 0; k < cols; k++) ...[
              if (k > 0) SizedBox(width: _spacing),
              Expanded(
                child: i + k < products.length
                    ? _card(products[i + k], itemWidth)
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ));
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: paddingH),
      child: Column(children: rows),
    );
  }

  Widget _staggered() {
    final cols = config.gridColumns.clamp(2, 3);
    final itemWidth = (_innerWidth - _spacing * (cols - 1)) / cols;
    final columns = List.generate(cols, (_) => <Widget>[]);
    for (var i = 0; i < products.length; i++) {
      // Setiap item ke-3 dibuat lebih tinggi supaya kolom saling "berselang".
      final ratio = i % 3 == 0 ? _style.imageRatio * 0.75 : _style.imageRatio;
      final column = columns[i % cols];
      if (column.isNotEmpty) column.add(SizedBox(height: _spacing));
      column.add(_card(products[i], itemWidth, fill: false, ratio: ratio));
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: paddingH),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var k = 0; k < cols; k++) ...[
            if (k > 0) SizedBox(width: _spacing),
            Expanded(child: Column(children: columns[k])),
          ],
        ],
      ),
    );
  }

  Widget _listTile() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: paddingH),
      child: Column(
        children: [
          for (var i = 0; i < products.length; i++) ...[
            if (i > 0) SizedBox(height: _spacing),
            ProductListTileCard(product: products[i], style: _style),
          ],
        ],
      ),
    );
  }

  Widget _simpleList() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: paddingH),
      child: Column(
        children: [
          for (var i = 0; i < products.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ProductSimpleRow(product: products[i], style: _style),
          ],
        ],
      ),
    );
  }

  Widget _quilted() {
    final colWidth = (_innerWidth - _spacing) / 2;
    final smallH = colWidth * 0.7;
    final bigH = smallH * 2 + _spacing;
    final groups = <Widget>[];

    Widget tile(Product p) => ProductImageTile(product: p, style: _style);

    for (var i = 0, g = 0; i < products.length; i += 3, g++) {
      final group = products.sublist(i, math.min(i + 3, products.length));
      if (groups.isNotEmpty) groups.add(SizedBox(height: _spacing));
      if (group.length == 3) {
        final big = Expanded(child: tile(group[0]));
        final smalls = Expanded(
          child: Column(
            children: [
              Expanded(child: tile(group[1])),
              SizedBox(height: _spacing),
              Expanded(child: tile(group[2])),
            ],
          ),
        );
        // Grup ganjil: tile besar di kanan, supaya polanya bervariasi.
        final children = g.isEven
            ? [big, SizedBox(width: _spacing), smalls]
            : [smalls, SizedBox(width: _spacing), big];
        groups.add(SizedBox(
          height: bigH,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ));
      } else {
        groups.add(SizedBox(
          height: smallH,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tile(group[0])),
              SizedBox(width: _spacing),
              Expanded(
                child: group.length > 1 ? tile(group[1]) : const SizedBox.shrink(),
              ),
            ],
          ),
        ));
      }
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: paddingH),
      child: Column(children: groups),
    );
  }
}

/// Carousel: kartu besar di tengah, kartu samping sedikit mengecil.
class _ProductCarousel extends StatefulWidget {
  final List<Product> products;
  final ProductBlockConfig config;
  final double fullWidth;

  const _ProductCarousel({
    required this.products,
    required this.config,
    required this.fullWidth,
  });

  @override
  State<_ProductCarousel> createState() => _ProductCarouselState();
}

class _ProductCarouselState extends State<_ProductCarousel> {
  static const double _viewport = 0.75;
  static const double _itemPadding = 6;

  final PageController _controller = PageController(viewportFraction: _viewport);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _ProductCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.autoSlide != widget.config.autoSlide ||
        oldWidget.products.length != widget.products.length) {
      _syncTimer();
    }
  }

  void _syncTimer() {
    _timer?.cancel();
    _timer = null;
    if (!widget.config.autoSlide || widget.products.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_controller.hasClients) return;
      final next = ((_controller.page ?? 0).round() + 1) % widget.products.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Perkiraan tinggi bagian teks kartu (gambar mengisi sisanya).
  double _infoHeight(BuildContext context) {
    final s = widget.config.card;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    var h = 0.0;
    if (s.showCategory) h += 15;
    if (s.showTitle) h += 17.0 * s.titleMaxLines;
    if (s.showStock) h += 15;
    if (s.showPrice || s.showCartButton) h += 38;
    if (s.design == 'simpleCard') h += 6;
    return h * scale + 30;
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.config.card;
    final itemWidth = widget.fullWidth * _viewport - _itemPadding * 2;
    final height = itemWidth / style.imageRatio + _infoHeight(context);

    return SizedBox(
      height: height + 8,
      child: PageView.builder(
        controller: _controller,
        itemCount: widget.products.length,
        itemBuilder: (context, index) {
          final card = Padding(
            padding: const EdgeInsets.fromLTRB(_itemPadding, 2, _itemPadding, 6),
            child: ConfigurableProductCard(
              product: widget.products[index],
              style: style,
              expandImage: true,
            ),
          );
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              var scale = index == 0 ? 1.0 : 0.92;
              if (_controller.hasClients && _controller.position.haveDimensions) {
                final page = _controller.page ?? 0;
                scale = (1 - (page - index).abs() * 0.08).clamp(0.9, 1.0);
              }
              return Transform.scale(scale: scale, child: child);
            },
            child: card,
          );
        },
      ),
    );
  }
}
