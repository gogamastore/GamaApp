import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/data/firestore_service.dart';
import '../domain/product.dart';
import '../application/promotion_provider.dart';
import '../../cart/application/cart_provider.dart';
import 'widgets/quantity_selector.dart';

class ProductDetailScreen extends StatefulWidget {
  final Product? product;
  final String? productId;

  const ProductDetailScreen({
    super.key,
    this.product,
    this.productId,
  }) : assert(product != null || productId != null, 'Either product or productId must be provided.');

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  Product? _product;
  Future<Product?>? _fetchProductFuture;
  int _selectedQuantity = 1;

  @override
  void initState() {
    super.initState();
    if (widget.product != null) {
      _product = widget.product;
    } else {
      final firestoreService = Provider.of<FirestoreService>(context, listen: false);
      _fetchProductFuture = firestoreService.getProduct(widget.productId!);
    }
    if (_product?.stock == 0) {
      _selectedQuantity = 0;
    }
  }

  void _onQuantityChanged(int newQuantity) {
    setState(() {
      _selectedQuantity = newQuantity;
    });
  }

  // --- FUNGSI BARU UNTUK MENANGANI PENAMBAHAN KE KERANJANG ---
  Future<void> _handleAddToCart() async {
    if (_product == null || _selectedQuantity <= 0) return;

    final cartProvider = context.read<CartProvider>();

    // Terapkan harga promo bila ada (produk dikirim dengan harga asli).
    final promo =
        context.read<PromotionProvider>().getPromotionForProduct(_product!.id);
    final double? discountPrice =
        (promo != null && promo.discountPrice < _product!.price)
            ? promo.discountPrice
            : null;

    final bool success = await cartProvider.addItemToCart(
      _product!,
      _selectedQuantity,
      discountPrice: discountPrice,
    );

    if (!mounted) return; // Pastikan widget masih ada di tree

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$_selectedQuantity x ${_product!.name} ditambahkan ke keranjang.'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Keranjang Penuh'),
          content: const Text('Maaf Keranjang Anda Penuh, harap checkout terlebih dahulu, lalu mengisi keranjang anda kembali. Terima Kasih'),
          actions: [
            TextButton(
              child: const Text('Mengerti'),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      );
    }
  }
  // --- AKHIR FUNGSI BARU ---

  @override
  Widget build(BuildContext context) {
    if (_product != null) {
      return _buildProductUI(_product!, context);
    }

    return FutureBuilder<Product?>(
      future: _fetchProductFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Error')),
            body: const Center(child: Text('Produk tidak dapat ditemukan.')),
          );
        }

        _product = snapshot.data;
        if (_product?.stock == 0) {
          _selectedQuantity = 0;
        }
        return _buildProductUI(_product!, context);
      },
    );
  }

  Widget _buildProductUI(Product product, BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_selectedQuantity > product.stock) {
      _selectedQuantity = product.stock;
    }
    if (product.stock > 0 && _selectedQuantity == 0) {
      _selectedQuantity = 1;
    }

    // --- Logika Promo (mirror halaman web reseller) ---
    final promo = context.watch<PromotionProvider>().getPromotionForProduct(product.id);
    final bool hasPromo = promo != null;
    final double originalPrice = product.price;
    final double discountedPrice = hasPromo ? promo.discountPrice : product.price;
    final bool showStrike = hasPromo && originalPrice > discountedPrice;
    final int discountPercent = showStrike
        ? (((originalPrice - discountedPrice) / originalPrice) * 100).round()
        : 0;
    final double displayPrice = hasPromo ? discountedPrice : product.price;

    final bool stockAvailable = product.stock > 0;
    final String weightLabel =
        product.weightGram > 0 ? '${product.weightGram} gram' : '200 gram';

    return Scaffold(
      appBar: AppBar(
        title: Text(product.name, overflow: TextOverflow.ellipsis),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Galeri gambar ---
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  children: [
                    Hero(
                      tag: 'product-image-${product.id}',
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: CachedNetworkImage(
                          imageUrl: product.imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          placeholder: (context, url) => Container(
                            color: Colors.grey[200],
                            child: const Center(child: CircularProgressIndicator()),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey[200],
                            child: const Center(
                                child: Icon(Icons.broken_image, size: 60, color: Colors.grey)),
                          ),
                        ),
                      ),
                    ),
                    if (showStrike && discountPercent > 0)
                      Positioned(
                        left: 14,
                        top: 14,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: colorScheme.error,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '-$discountPercent%',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colorScheme.onError,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // --- Kategori + nama ---
              if (product.category.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    product.category,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                product.name,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              // --- Rating + terjual + SKU ---
              Row(
                children: [
                  ...List.generate(
                    5,
                    (_) => const Icon(Icons.star, size: 16, color: Color(0xFFFBBF24)),
                  ),
                  const SizedBox(width: 8),
                  Text('·', style: TextStyle(color: Colors.grey[500])),
                  const SizedBox(width: 8),
                  Text('Terjual banyak',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                  if (product.sku.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text('·', style: TextStyle(color: Colors.grey[500])),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text('SKU ${product.sku}',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              // --- Blok harga ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            currencyFormatter.format(displayPrice),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (showStrike && discountPercent > 0) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: colorScheme.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '-$discountPercent%',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.error,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (showStrike) ...[
                      const SizedBox(height: 4),
                      Text(
                        currencyFormatter.format(originalPrice),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: Colors.grey[600],
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // --- Chip highlight ---
              Row(
                children: [
                  Expanded(
                    child: _highlightChip(
                      theme,
                      icon: Icons.inventory_2_outlined,
                      label: 'Stok',
                      value: stockAvailable ? '${product.stock} tersedia' : 'Habis',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _highlightChip(
                      theme,
                      icon: Icons.scale_outlined,
                      label: 'Berat',
                      value: weightLabel,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _highlightChip(
                      theme,
                      icon: Icons.local_shipping_outlined,
                      label: 'Dikirim dari',
                      value: 'Makassar',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _highlightChip(
                      theme,
                      icon: Icons.sell_outlined,
                      label: 'Kategori',
                      value: product.category.isNotEmpty ? product.category : 'Umum',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // --- Trust badges ---
              Wrap(
                spacing: 20,
                runSpacing: 8,
                children: [
                  _trustBadge(theme, Icons.verified_user_outlined, 'Produk Original',
                      Colors.green),
                  _trustBadge(theme, Icons.replay_outlined, 'Garansi Toko', Colors.blue),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),

              // --- Deskripsi ---
              Text('Deskripsi Produk',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                product.description.isNotEmpty
                    ? product.description
                    : 'Tidak ada deskripsi untuk produk ini.',
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.6, color: Colors.grey[800]),
              ),
              const SizedBox(height: 20),

              // --- Spesifikasi ---
              Text('Spesifikasi',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _specRow(theme, 'Kategori', product.category.isNotEmpty ? product.category : '-'),
              _specRow(theme, 'Berat', weightLabel),
              if (product.sku.isNotEmpty) _specRow(theme, 'SKU', product.sku),
              _specRow(theme, 'Stok', stockAvailable ? '${product.stock} tersedia' : 'Habis'),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (product.stock > 0)
                QuantitySelector(
                  quantity: _selectedQuantity,
                  stock: product.stock,
                  onChanged: _onQuantityChanged,
                ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                // --- PERUBAHAN: Panggil fungsi _handleAddToCart ---
                onPressed: _selectedQuantity > 0 ? _handleAddToCart : null,
                icon: const Icon(Icons.add_shopping_cart),
                label: Text(stockAvailable ? 'Tambah ke Keranjang' : 'Stok Habis'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _highlightChip(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _trustBadge(ThemeData theme, IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[700])),
      ],
    );
  }

  Widget _specRow(ThemeData theme, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
