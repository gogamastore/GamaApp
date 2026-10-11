import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/data/firestore_service.dart';
import '../../products/domain/product.dart';
import '../../products/presentation/widgets/product_card.dart';

/// Halaman "Lihat Semua" untuk blok produk / kategori / brand di beranda.
class ProductCollectionScreen extends StatefulWidget {
  final String title;
  final String source;
  final String category;
  final String brandId;

  const ProductCollectionScreen({
    super.key,
    required this.title,
    required this.source,
    this.category = '',
    this.brandId = '',
  });

  @override
  State<ProductCollectionScreen> createState() => _ProductCollectionScreenState();
}

class _ProductCollectionScreenState extends State<ProductCollectionScreen> {
  late final Stream<List<Product>> _stream =
      context.read<FirestoreService>().getProductsForSource(
            source: widget.source,
            category: widget.category,
            brandId: widget.brandId,
            limit: 200,
          );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: StreamBuilder<List<Product>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Gagal memuat produk: ${snapshot.error}',
                    textAlign: TextAlign.center),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          // Produk tersedia lebih dulu, sama seperti katalog.
          final products = List<Product>.of(snapshot.data!)
            ..sort((a, b) {
              final aReady = a.stock > 0;
              final bReady = b.stock > 0;
              if (aReady != bReady) return aReady ? -1 : 1;
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });
          if (products.isEmpty) {
            return const Center(child: Text('Belum ada produk di sini.'));
          }
          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.55,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: products.length,
            itemBuilder: (context, index) => ProductCard(product: products[index]),
          );
        },
      ),
    );
  }
}
