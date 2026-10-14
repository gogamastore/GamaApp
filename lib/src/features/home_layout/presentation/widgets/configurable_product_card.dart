import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../cart/application/cart_provider.dart';
import '../../../products/application/promotion_provider.dart';
import '../../../products/domain/product.dart';
import '../../application/app_layout_provider.dart';
import '../../domain/app_layout.dart';

final NumberFormat _rupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// Harga efektif sebuah produk (memperhitungkan promo aktif).
class _Pricing {
  final bool hasPromo;
  final double price;
  final double original;
  final int percent;

  const _Pricing(this.hasPromo, this.price, this.original, this.percent);

  factory _Pricing.of(BuildContext context, Product product) {
    final promo =
        context.watch<PromotionProvider>().getPromotionForProduct(product.id);
    final hasPromo = promo != null &&
        product.price > 0 &&
        promo.discountPrice > 0 &&
        promo.discountPrice < product.price;
    if (!hasPromo) return _Pricing(false, product.price, product.price, 0);
    final percent = ((1 - promo.discountPrice / product.price) * 100).round();
    return _Pricing(true, promo.discountPrice, product.price, percent);
  }
}

void _openProduct(BuildContext context, Product product) {
  // Sama dengan ProductCard lama: produk habis tidak bisa dibuka. Produk
  // dikirim dengan harga ASLI; halaman detail menghitung promo sendiri.
  if (product.stock <= 0) return;
  context.push('/product/${product.id}', extra: product);
}

Color _priceColor(BuildContext context) =>
    context.select<AppLayoutProvider, Color?>((p) => p.design.priceColor) ??
    Theme.of(context).colorScheme.primary;

/// Gambar produk + overlay "Stok Habis" + badge diskon.
class _ProductImage extends StatelessWidget {
  final Product product;
  final _Pricing pricing;
  final ProductCardStyle style;
  final double radius;
  final bool compact;

  const _ProductImage({
    required this.product,
    required this.pricing,
    required this.style,
    required this.radius,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget image = Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: style.imageFit == BoxFit.contain ? Colors.white : Colors.grey.shade100,
          child: CachedNetworkImage(
            imageUrl: product.imageUrl,
            fit: style.imageFit,
            placeholder: (context, url) => const SizedBox.shrink(),
            errorWidget: (context, url, error) =>
                const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
          ),
        ),
        if (product.stock <= 0)
          Container(
            color: Colors.black.withAlpha(128),
            alignment: Alignment.center,
            child: Text(
              'Stok Habis',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: compact ? 11 : 13,
              ),
            ),
          ),
        if (pricing.hasPromo && style.showDiscountBadge)
          Positioned(
            top: 6,
            left: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '-${pricing.percent}%',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: compact ? 9 : 11,
                ),
              ),
            ),
          ),
      ],
    );
    if (radius > 0) {
      image = ClipRRect(borderRadius: BorderRadius.circular(radius), child: image);
    }
    return image;
  }
}

/// Tombol kecil "tambah ke keranjang" (qty 1).
class _CartButton extends StatelessWidget {
  final Product product;
  final _Pricing pricing;
  final double size;

  const _CartButton({required this.product, required this.pricing, this.size = 30});

  Future<void> _add(BuildContext context) async {
    final cart = context.read<CartProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final result = await cart.addItemToCart(
      product,
      1,
      discountPrice: pricing.hasPromo ? pricing.price : null,
    );
    final message = switch (result) {
      AddToCartResult.success => '${product.name} ditambahkan ke keranjang',
      AddToCartResult.cartFull => 'Keranjang penuh (maksimal 160 produk).',
      AddToCartResult.insufficientStock => 'Stok tidak mencukupi.',
      AddToCartResult.notLoggedIn => 'Silakan login terlebih dahulu.',
    };
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        // Warna tombol utama dari App Builder (sama dengan ElevatedButton).
        color: Theme.of(context)
                .elevatedButtonTheme
                .style
                ?.backgroundColor
                ?.resolve(const <WidgetState>{}) ??
            Theme.of(context).colorScheme.primary,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _add(context),
          child: Icon(Icons.add_shopping_cart, size: size * 0.55, color: Colors.white),
        ),
      ),
    );
  }
}

/// Teks info produk: kategori, nama, stok, harga, tombol keranjang.
class _ProductInfo extends StatelessWidget {
  final Product product;
  final _Pricing pricing;
  final ProductCardStyle style;
  final bool compact;
  final bool centered;
  final bool pillPrice;
  final bool fillHeight;

  const _ProductInfo({
    required this.product,
    required this.pricing,
    required this.style,
    required this.compact,
    this.centered = false,
    this.pillPrice = false,
    this.fillHeight = false,
  });

  @override
  Widget build(BuildContext context) {
    final titleSize = compact ? 11.0 : 13.0;
    final priceSize = compact ? 12.0 : 14.0;
    final smallSize = compact ? 9.5 : 11.0;
    final align = centered ? TextAlign.center : TextAlign.start;
    final isOutOfStock = product.stock <= 0;

    final texts = <Widget>[
      if (style.showCategory && product.category.isNotEmpty)
        Text(
          product.category,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: TextStyle(fontSize: smallSize, color: Colors.grey[600]),
        ),
      if (style.showTitle)
        Text(
          product.name,
          maxLines: style.titleMaxLines,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: TextStyle(
              fontSize: titleSize, fontWeight: FontWeight.w600, height: 1.25),
        ),
      if (style.showRating && product.ratingCount > 0)
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment:
              centered ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            Icon(Icons.star, size: smallSize + 2, color: const Color(0xFFFBBF24)),
            const SizedBox(width: 2),
            Text(
              '${product.ratingAvg.toStringAsFixed(1)} (${product.ratingCount})',
              style: TextStyle(
                  fontSize: smallSize, color: Colors.grey[700], fontWeight: FontWeight.w600),
            ),
          ],
        ),
      if (style.showStock)
        Text(
          isOutOfStock ? 'Stok Habis' : 'Stok: ${product.stock}',
          textAlign: align,
          style: TextStyle(
            fontSize: smallSize,
            fontWeight: FontWeight.w600,
            color: isOutOfStock ? Colors.red[700] : Colors.green[700],
          ),
        ),
    ];

    Widget? price;
    if (style.showPrice) {
      final current = Text(
        _rupiah.format(pricing.price),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: TextStyle(
          fontSize: priceSize,
          fontWeight: FontWeight.bold,
          color: _priceColor(context),
        ),
      );
      price = pricing.hasPromo
          ? Column(
              crossAxisAlignment:
                  centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _rupiah.format(pricing.original),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: priceSize - 3,
                    color: Colors.grey[500],
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                current,
              ],
            )
          : current;
      if (pillPrice) {
        price = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(20),
          ),
          child: price,
        );
      }
    }
    final cart = style.showCartButton && !isOutOfStock
        ? _CartButton(product: product, pricing: pricing, size: compact ? 24 : 30)
        : null;

    return Column(
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < texts.length; i++) ...[
          if (i > 0) const SizedBox(height: 2),
          texts[i],
        ],
        if (fillHeight) const Spacer(),
        if (price != null || cart != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Align(
                    alignment: centered ? Alignment.center : Alignment.centerLeft,
                    child: price ?? const SizedBox.shrink(),
                  ),
                ),
                if (cart != null) ...[const SizedBox(width: 4), cart],
              ],
            ),
          ),
      ],
    );
  }
}

/// Kartu produk yang tampilannya mengikuti [ProductCardStyle] dari
/// App Builder.
class ConfigurableProductCard extends StatelessWidget {
  final Product product;
  final ProductCardStyle style;
  final bool compact;

  /// true bila tinggi kartu ditentukan parent (IntrinsicHeight / ukuran
  /// tetap) → harga didorong ke bawah agar sejajar antar kartu.
  final bool fillHeight;

  /// true bila gambar harus mengisi sisa tinggi (carousel ukuran tetap).
  final bool expandImage;

  /// Rasio gambar khusus (dipakai layout staggered).
  final double? imageRatio;

  const ConfigurableProductCard({
    super.key,
    required this.product,
    required this.style,
    this.compact = false,
    this.fillHeight = false,
    this.expandImage = false,
    this.imageRatio,
  });

  Widget _sizedImage(Widget image, EdgeInsets padding) {
    final padded = padding == EdgeInsets.zero ? image : Padding(padding: padding, child: image);
    if (expandImage) return Expanded(child: padded);
    return Padding(
      padding: padding,
      child: AspectRatio(aspectRatio: imageRatio ?? style.imageRatio, child: image),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pricing = _Pricing.of(context, product);
    final isSimple = style.design == 'simpleCard' || style.design == 'flatSimple';
    return isSimple ? _buildSimple(context, pricing) : _buildBoxed(context, pricing);
  }

  // card | glass | flat — gambar & info di dalam kotak berlatar.
  Widget _buildBoxed(BuildContext context, _Pricing pricing) {
    final isGlass = style.design == 'glass';
    final isFlat = style.design == 'flat';
    final radius = BorderRadius.circular(style.radius);
    final inset = style.imageRounded;
    final background = isGlass
        ? (style.cardColor ?? Colors.white).withValues(alpha: 0.55)
        : (style.cardColor ?? Colors.white);

    final image = _sizedImage(
      _ProductImage(
        product: product,
        pricing: pricing,
        style: style,
        radius: inset ? math.max(style.radius - 4, 4) : 0,
        compact: compact,
      ),
      inset ? const EdgeInsets.fromLTRB(6, 6, 6, 0) : EdgeInsets.zero,
    );
    final info = Padding(
      padding: EdgeInsets.fromLTRB(8, 6, 8, compact ? 6 : 8),
      child: _ProductInfo(
        product: product,
        pricing: pricing,
        style: style,
        compact: compact,
        fillHeight: fillHeight,
      ),
    );

    Widget content = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => _openProduct(context, product),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [image, if (fillHeight) Expanded(child: info) else info],
        ),
      ),
    );
    if (isGlass) {
      content = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: ColoredBox(color: background, child: content),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isGlass ? null : background,
        borderRadius: radius,
        border: isFlat
            ? Border.all(color: const Color(0xFFE5E7EB))
            : isGlass
                ? Border.all(color: Colors.white.withValues(alpha: 0.7))
                : null,
        boxShadow: style.boxShadow,
      ),
      child: ClipRRect(borderRadius: radius, child: content),
    );
  }

  // simpleCard | flatSimple — tanpa kotak; gambar berdiri sendiri.
  Widget _buildSimple(BuildContext context, _Pricing pricing) {
    final isSimpleCard = style.design == 'simpleCard';
    final imageRadius = style.imageRounded ? style.radius : 0.0;

    Widget image = _ProductImage(
      product: product,
      pricing: pricing,
      style: style,
      radius: imageRadius,
      compact: compact,
    );
    if (isSimpleCard && style.shadowEnabled) {
      image = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(imageRadius),
          boxShadow: style.boxShadow,
        ),
        child: image,
      );
    }

    final info = Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 4),
      child: _ProductInfo(
        product: product,
        pricing: pricing,
        style: style,
        compact: compact,
        centered: isSimpleCard,
        pillPrice: isSimpleCard,
        fillHeight: fillHeight,
      ),
    );

    Widget content = Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(style.radius),
        onTap: () => _openProduct(context, product),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _sizedImage(image, EdgeInsets.zero),
            if (fillHeight) Expanded(child: info) else info,
          ],
        ),
      ),
    );
    if (style.cardColor != null) {
      content = Container(
        decoration: BoxDecoration(
          color: style.cardColor,
          borderRadius: BorderRadius.circular(style.radius),
        ),
        child: content,
      );
    }
    return content;
  }
}

/// Baris produk dengan gambar di kiri (layout "List Tile").
class ProductListTileCard extends StatelessWidget {
  final Product product;
  final ProductCardStyle style;

  const ProductListTileCard({super.key, required this.product, required this.style});

  @override
  Widget build(BuildContext context) {
    final pricing = _Pricing.of(context, product);
    final isBoxed = style.design != 'flatSimple' && style.design != 'simpleCard';
    final radius = BorderRadius.circular(style.radius);

    final row = Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: AspectRatio(
              aspectRatio: style.imageRatio,
              child: _ProductImage(
                product: product,
                pricing: pricing,
                style: style,
                radius: style.imageRounded ? math.max(style.radius - 4, 4) : 0,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ProductInfo(product: product, pricing: pricing, style: style, compact: false),
          ),
        ],
      ),
    );

    final content = Material(
      type: MaterialType.transparency,
      child: InkWell(onTap: () => _openProduct(context, product), child: row),
    );
    if (!isBoxed) return content;
    return Container(
      decoration: BoxDecoration(
        color: style.cardColor ?? Colors.white,
        borderRadius: radius,
        border: style.design == 'flat' ? Border.all(color: const Color(0xFFE5E7EB)) : null,
        boxShadow: style.boxShadow,
      ),
      child: ClipRRect(borderRadius: radius, child: content),
    );
  }
}

/// Baris ringkas: thumbnail kecil + nama + harga (layout "Simple List").
class ProductSimpleRow extends StatelessWidget {
  final Product product;
  final ProductCardStyle style;

  const ProductSimpleRow({super.key, required this.product, required this.style});

  @override
  Widget build(BuildContext context) {
    final pricing = _Pricing.of(context, product);
    return InkWell(
      onTap: () => _openProduct(context, product),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: _ProductImage(
                product: product,
                pricing: pricing,
                style: style,
                radius: style.imageRounded ? 8 : 0,
                compact: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ProductInfo(
                product: product,
                pricing: pricing,
                style: style,
                compact: true,
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

/// Tile gambar penuh dengan teks di atas gradien (layout "Quilted").
class ProductImageTile extends StatelessWidget {
  final Product product;
  final ProductCardStyle style;

  const ProductImageTile({super.key, required this.product, required this.style});

  @override
  Widget build(BuildContext context) {
    final pricing = _Pricing.of(context, product);
    final radius = BorderRadius.circular(style.radius);
    return Container(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: style.boxShadow),
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => _openProduct(context, product),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _ProductImage(product: product, pricing: pricing, style: style, radius: 0),
                if (style.showTitle || style.showPrice)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black.withValues(alpha: 0.65), Colors.transparent],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (style.showTitle)
                            Text(
                              product.name,
                              maxLines: style.titleMaxLines,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (style.showPrice)
                            Text(
                              _rupiah.format(pricing.price),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
