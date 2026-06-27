import 'dart:developer' as developer; // Impor untuk logging
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

import '../../domain/product.dart';
import '../../application/promotion_provider.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final bool isProductClickable;
  final bool enableHero;

  const ProductCard({
    super.key,
    required this.product,
    this.isProductClickable = true,
    this.enableHero = true,
  });

  @override
  Widget build(BuildContext context) {
    final NumberFormat currencyFormatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    final theme = Theme.of(context);
    final bool isOutOfStock = product.stock <= 0;

    // --- PERANGKAP DEBUG DIMULAI DI SINI ---
    if (product.price <= 0) {
      developer.log(
        '[PERINGATAN DATA] Produk berikut memiliki harga 0 atau negatif, yang dapat menyebabkan error kalkulasi. Harap perbaiki di Firestore.',
        name: 'Data.ProductPriceError',
        error: 'ID: ${product.id}, Nama: ${product.name}, Harga: ${product.price}',
      );
    }
    // --- PERANGKAP DEBUG BERAKHIR DI SINI ---

    final promoProvider = context.watch<PromotionProvider>();
    final promotion = promoProvider.getPromotionForProduct(product.id);
    final discountedPrice = promotion?.discountPrice;
    
    final hasPromo = promotion != null && discountedPrice != null && product.price > 0;

    void handleTap() {
      if (isProductClickable && !isOutOfStock) {
        // Kirim produk dengan harga ASLI. Halaman detail menampilkan diskon
        // via PromotionProvider, sehingga harga coret + badge persen muncul.
        context.push('/product/${product.id}', extra: product);
      }
    }

    Widget imageWidget = Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: product.imageUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) =>
              const Center(child: CircularProgressIndicator()),
          errorWidget: (context, url, error) =>
              const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
        ),
        if (isOutOfStock)
          Container(
            color: Colors.black.withAlpha(128),
            alignment: Alignment.center,
            child: const Text(
              'Stok Habis',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        if (hasPromo)
          Align(
            alignment: Alignment.topLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(230),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: const Text(
                'PROMO',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ),
          ),
      ],
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: handleTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1.0,
              child: enableHero
                  ? Hero(
                      tag: 'product-image-${product.id}',
                      child: imageWidget,
                    )
                  : imageWidget,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: IntrinsicHeight(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product.name,
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    product.category,
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: Colors.grey[600]),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Stok: ${product.stock}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: product.stock > 0
                                          ? Colors.green[700]
                                          : Colors.red[700],
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              if (hasPromo)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      currencyFormatter.format(product.price),
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        decoration: TextDecoration.lineThrough,
                                        color: Colors.red[400],
                                        fontSize: 11,
                                      ),
                                    ),
                                    Text(
                                      currencyFormatter.format(discountedPrice),
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        color: theme.colorScheme.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Text(
                                  currencyFormatter.format(product.price),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
