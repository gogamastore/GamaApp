import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/data/firestore_service.dart';
import '../../home_layout/presentation/block_frame.dart';
import '../domain/brand.dart';

/// Halaman "Lihat Semua" brand — grid logo semua brand. Ketuk → produk brand.
class BrandsListScreen extends StatelessWidget {
  const BrandsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final stream = context.read<FirestoreService>().getBrandsStream();
    return Scaffold(
      appBar: AppBar(title: const Text('Semua Brand')),
      body: StreamBuilder<List<Brand>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Gagal memuat brand.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final brands = snapshot.data!;
          if (brands.isEmpty) {
            return const Center(child: Text('Belum ada brand.'));
          }
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 140,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
            itemCount: brands.length,
            itemBuilder: (context, i) {
              final brand = brands[i];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => context.push(
                    collectionLink(source: 'brand', brandId: brand.id, title: brand.name),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: brand.logoUrl.isEmpty
                              ? const Center(
                                  child: Icon(Icons.business, color: Colors.grey, size: 32))
                              : Image.network(
                                  brand.logoUrl,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(Icons.business, color: Colors.grey, size: 32),
                                ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                        child: Text(
                          brand.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
