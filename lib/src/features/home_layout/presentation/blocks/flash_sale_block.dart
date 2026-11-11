import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../flash_sale/application/flash_sale_provider.dart';
import '../../../flash_sale/domain/flash_sale.dart';
import '../../../products/domain/product.dart';
import '../../../../core/data/firestore_service.dart';
import '../../application/app_layout_provider.dart';
import '../../domain/app_layout.dart';
import '../block_frame.dart';

final NumberFormat _rupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// Blok "Flash Sale" di beranda — menampilkan event aktif/teaser secara
/// realtime. Teaser = harga tersensor; aktif = harga asli. Hitung mundur
/// & transisi waktu ditangani timer lokal (1 detik) di widget ini.
class FlashSaleBlockView extends StatefulWidget {
  final HomeBlock block;

  const FlashSaleBlockView({super.key, required this.block});

  @override
  State<FlashSaleBlockView> createState() => _FlashSaleBlockViewState();
}

class _FlashSaleBlockViewState extends State<FlashSaleBlockView> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FlashSaleProvider>();
    final event = provider.pickEvent(_now);
    if (event == null) return const SizedBox.shrink();

    final status = event.statusAt(_now);
    final censored = status == FlashSaleStatus.teaser;
    final cfg = FlashSaleBlockConfig.fromConfig(widget.block.config);
    final pad = widget.block.style.paddingH;

    final target = censored ? event.startAt : event.endAt;
    final remaining = target.difference(_now);

    return BlockFrame(
      block: widget.block,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _FlashHeader(
              title: event.title,
              remaining: remaining,
              label: censored ? 'Mulai dalam' : 'Berakhir dalam',
              showCountdown: cfg.showCountdown,
            ),
            if (censored)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 2),
                child: Text(
                  'Flash sale segera dimulai — Hanya Bisa Membeli 1 Produk Flash Sale.',
                  style: TextStyle(fontSize: 11, color: Colors.amber[800]),
                ),
              ),
            const SizedBox(height: 8),
            _FlashProducts(
              key: ValueKey(event.id),
              event: event,
              censored: censored,
              config: cfg,
            ),
          ],
        ),
      ),
    );
  }
}

class _FlashHeader extends StatelessWidget {
  final String title;
  final Duration remaining;
  final String label;
  final bool showCountdown;

  const _FlashHeader({
    required this.title,
    required this.remaining,
    required this.label,
    required this.showCountdown,
  });

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final secs = remaining.isNegative ? 0 : remaining.inSeconds;
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;

    Widget cell(String v) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(v,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0x1AF43F5E), Color(0x1AF59E0B)],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.flash_on, size: 18, color: Color(0xFFE11D48)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Color(0xFFE11D48)),
            ),
          ),
          if (showCountdown) ...[
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700])),
            const SizedBox(width: 6),
            cell(_two(h)),
            const Text(':', style: TextStyle(fontWeight: FontWeight.bold)),
            cell(_two(m)),
            const Text(':', style: TextStyle(fontWeight: FontWeight.bold)),
            cell(_two(s)),
          ],
        ],
      ),
    );
  }
}

/// Memuat detail produk event (realtime) lalu menampilkannya dalam grid.
class _FlashProducts extends StatefulWidget {
  final FlashSale event;
  final bool censored;
  final FlashSaleBlockConfig config;

  const _FlashProducts({
    super.key,
    required this.event,
    required this.censored,
    required this.config,
  });

  @override
  State<_FlashProducts> createState() => _FlashProductsState();
}

class _FlashProductsState extends State<_FlashProducts> {
  Stream<List<Product>>? _stream;
  String _key = '';

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant _FlashProducts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_signature(widget.event) != _key) _subscribe();
  }

  String _signature(FlashSale e) => e.products.map((p) => p.productId).join(',');

  void _subscribe() {
    _key = _signature(widget.event);
    _stream = context
        .read<FirestoreService>()
        .getProductsByIdsStream(widget.event.productIds.toList());
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Product>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        // Urutkan sesuai urutan produk di event + potong sesuai limit.
        final byId = {for (final p in snapshot.data!) p.id: p};
        final products = widget.event.products
            .map((it) => byId[it.productId])
            .whereType<Product>()
            .take(widget.config.limit)
            .toList();
        if (products.isEmpty) return const SizedBox.shrink();

        final priceColor =
            context.select<AppLayoutProvider, Color?>((p) => p.design.priceColor) ??
                Theme.of(context).colorScheme.primary;

        return LayoutBuilder(
          builder: (context, constraints) {
            final cols = widget.config.gridColumns.clamp(1, 4);
            const spacing = 8.0;
            final itemWidth = (constraints.maxWidth - spacing * (cols - 1)) / cols;
            final rows = <Widget>[];
            for (var i = 0; i < products.length; i += cols) {
              if (rows.isNotEmpty) rows.add(const SizedBox(height: spacing));
              rows.add(IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var k = 0; k < cols; k++) ...[
                      if (k > 0) const SizedBox(width: spacing),
                      Expanded(
                        child: i + k < products.length
                            ? _FlashCard(
                                product: products[i + k],
                                flashPrice: widget.event
                                        .flashPriceFor(products[i + k].id) ??
                                    products[i + k].price,
                                censored: widget.censored,
                                style: widget.config.card,
                                priceColor: priceColor,
                                compact: itemWidth < 120,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ));
            }
            return Column(children: rows);
          },
        );
      },
    );
  }
}

/// Kartu produk flash sale: harga asli saat aktif, tersensor saat teaser.
class _FlashCard extends StatelessWidget {
  final Product product;
  final double flashPrice;
  final bool censored;
  final ProductCardStyle style;
  final Color priceColor;
  final bool compact;

  const _FlashCard({
    required this.product,
    required this.flashPrice,
    required this.censored,
    required this.style,
    required this.priceColor,
    required this.compact,
  });

  void _open(BuildContext context) {
    if (product.stock <= 0) return;
    context.push('/product/${product.id}', extra: product);
  }

  @override
  Widget build(BuildContext context) {
    final out = product.stock <= 0;
    final normal = product.price;
    final percent = (normal > 0 && flashPrice > 0)
        ? ((1 - flashPrice / normal) * 100).round()
        : 0;
    final radius = BorderRadius.circular(style.radius);

    final image = AspectRatio(
      aspectRatio: style.imageRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: Colors.grey.shade100,
            child: CachedNetworkImage(
              imageUrl: product.imageUrl,
              fit: style.imageFit,
              placeholder: (_, __) => const SizedBox.shrink(),
              errorWidget: (_, __, ___) =>
                  const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
            ),
          ),
          if (out)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              alignment: Alignment.center,
              child: const Text('Stok Habis',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          Positioned(
            top: 6,
            left: 6,
            child: censored
                ? _badge('SEGERA', const Color(0xFFF59E0B))
                : (percent > 0 && style.showDiscountBadge
                    ? _badge('-$percent%', Colors.red)
                    : const SizedBox.shrink()),
          ),
        ],
      ),
    );

    final priceWidget = censored
        ? Text(
            censorFlashPrice(flashPrice),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 12 : 14,
              fontWeight: FontWeight.bold,
              color: priceColor,
              letterSpacing: 1.5,
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (percent > 0)
                Text(
                  _rupiah.format(normal),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: (compact ? 12 : 14) - 3,
                    color: Colors.grey[500],
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              Text(
                _rupiah.format(flashPrice),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 12 : 14,
                  fontWeight: FontWeight.bold,
                  color: priceColor,
                ),
              ),
            ],
          );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: radius,
        boxShadow: style.boxShadow,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => _open(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                image,
                Padding(
                  padding: EdgeInsets.fromLTRB(8, 6, 8, compact ? 6 : 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (style.showTitle)
                        Text(
                          product.name,
                          maxLines: style.titleMaxLines,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: compact ? 11 : 13,
                              fontWeight: FontWeight.w600,
                              height: 1.25),
                        ),
                      const SizedBox(height: 4),
                      priceWidget,
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration:
            BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
      );
}
