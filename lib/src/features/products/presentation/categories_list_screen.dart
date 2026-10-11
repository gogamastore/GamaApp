import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/data/firestore_service.dart';
import '../../home_layout/presentation/block_frame.dart';

typedef _Category = ({String id, String name, String imageUrl});

/// Halaman "Lihat Semua" kategori — grid semua kategori dengan ikon gambar
/// bawaannya (fallback huruf awal bila belum ada gambar). Ketuk → produk
/// kategori tsb.
class CategoriesListScreen extends StatelessWidget {
  const CategoriesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final stream = context.read<FirestoreService>().getCategoriesStream();
    final color = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('Semua Kategori')),
      body: StreamBuilder<List<_Category>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Gagal memuat kategori.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final categories = snapshot.data!;
          if (categories.isEmpty) {
            return const Center(child: Text('Belum ada kategori.'));
          }
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 110,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.8,
            ),
            itemCount: categories.length,
            itemBuilder: (context, i) {
              final cat = categories[i];
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => context.push(
                  collectionLink(source: 'category', category: cat.name, title: cat.name),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
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
                                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 24),
                              ),
                            )
                          : Text(
                              cat.name.characters.first.toUpperCase(),
                              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 24),
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
              );
            },
          );
        },
      ),
    );
  }
}
