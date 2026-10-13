import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/data/firestore_service.dart';
import '../../home_layout/presentation/block_frame.dart';
import '../domain/product.dart';
import 'widgets/product_card.dart';

typedef _Category = ({String id, String name, String imageUrl});

/// Daftar SUB-KATEGORI dari satu induk kategori + SEMUA produk dari seluruh
/// sub-kategorinya langsung di halaman yang sama. Dibuka saat induk kategori
/// diketuk (blok "Induk Kategori"). Ketuk sub-kategori → produk kategori tsb.
class ParentSubcategoriesScreen extends StatefulWidget {
  final String parentId;
  final String parentName;

  const ParentSubcategoriesScreen({
    super.key,
    required this.parentId,
    required this.parentName,
  });

  @override
  State<ParentSubcategoriesScreen> createState() =>
      _ParentSubcategoriesScreenState();
}

class _ParentSubcategoriesScreenState extends State<ParentSubcategoriesScreen> {
  Set<String>? _childNames; // null = masih memuat
  late final FirestoreService _service;

  @override
  void initState() {
    super.initState();
    _service = context.read<FirestoreService>();
    _loadChildren();
  }

  Future<void> _loadChildren() async {
    final parent = await _service.getParentCategory(widget.parentId);
    if (!mounted) return;
    setState(() => _childNames = (parent?.children ?? const <String>[]).toSet());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.parentName.isEmpty ? 'Kategori' : widget.parentName),
      ),
      body: _childNames == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                _buildSubcategories(),
                _buildProducts(),
              ],
            ),
    );
  }

  /// Baris sub-kategori milik induk ini (geser horizontal, ringkas).
  Widget _buildSubcategories() {
    final color = Theme.of(context).colorScheme.primary;
    return StreamBuilder<List<_Category>>(
      stream: _service.getCategoriesStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
        }
        final categories =
            snapshot.data!.where((c) => _childNames!.contains(c.name)).toList();
        if (categories.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text('Sub-kategori',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final cat = categories[i];
                  return SizedBox(
                    width: 76,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => context.push(
                        collectionLink(
                            source: 'category', category: cat.name, title: cat.name),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: cat.imageUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: cat.imageUrl,
                                    fit: BoxFit.contain,
                                    errorWidget: (context, url, error) => Text(
                                      cat.name.characters.first.toUpperCase(),
                                      style: TextStyle(
                                          color: color,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 22),
                                    ),
                                  )
                                : Text(
                                    cat.name.characters.first.toUpperCase(),
                                    style: TextStyle(
                                        color: color,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 22),
                                  ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            cat.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11, height: 1.2),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// Semua produk dari seluruh sub-kategori induk ini.
  Widget _buildProducts() {
    final childNames = _childNames ?? const <String>{};
    return StreamBuilder<List<Product>>(
      stream: _service.getProductsStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('Gagal memuat produk.')),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final products = snapshot.data!
            .where((p) => childNames.contains(p.category))
            .toList()
          ..sort((a, b) {
            final aReady = a.stock > 0;
            final bReady = b.stock > 0;
            if (aReady != bReady) return aReady ? -1 : 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });

        final title = widget.parentName.isEmpty ? 'Produk' : 'Produk ${widget.parentName}';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            if (products.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Belum ada produk di kategori ini.')),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.55,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: products.length,
                itemBuilder: (context, index) => ProductCard(product: products[index]),
              ),
          ],
        );
      },
    );
  }
}
