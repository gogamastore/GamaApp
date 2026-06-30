import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/data/firestore_service.dart';
import '../domain/product.dart';
import 'widgets/product_card.dart';
import 'widgets/product_list_card.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late final FirestoreService _firestoreService;
  Stream<List<Product>>? _productsStream;
  String _searchQuery = '';
  bool _isGridView = true; // tampilan default: grid

  @override
  void initState() {
    super.initState();
    _firestoreService = Provider.of<FirestoreService>(context, listen: false);
    _productsStream = _firestoreService.getProductsStream();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        // Kotak pencarian ala Shopee: pill putih dengan ikon search.
        title: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 20, color: Colors.grey[500]),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                  textAlignVertical: TextAlignVertical.center,
                  decoration: InputDecoration(
                    hintText: 'Cari produk...',
                    border: InputBorder.none,
                    isCollapsed: true,
                    hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                  ),
                  style: const TextStyle(color: Colors.black87, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
        actions: [
          // Tombol ubah tampilan grid ⇄ list.
          IconButton(
            tooltip: _isGridView ? 'Tampilan daftar' : 'Tampilan grid',
            icon: Icon(
              _isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
            ),
            onPressed: () => setState(() => _isGridView = !_isGridView),
          ),
        ],
      ),
      body: StreamBuilder<List<Product>>(
        stream: _productsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Gagal memuat produk. Penyebab: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red[700]),
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          var products = snapshot.data ?? [];

          // --- LOGIKA SORTIR BARU DIMULAI DI SINI ---
          products.sort((a, b) {
            // Prioritas 1: Produk dengan stok > 0 (Tersedia) diutamakan.
            final aTersedia = a.stock > 0;
            final bTersedia = b.stock > 0;

            if (aTersedia && !bTersedia) {
              return -1; // a (tersedia) diletakkan sebelum b (habis).
            }
            if (!aTersedia && bTersedia) {
              return 1; // a (habis) diletakkan setelah b (tersedia).
            }

            // Prioritas 2: Jika status stok sama, urutkan berdasarkan nama (A-Z).
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
          // --- LOGIKA SORTIR BARU BERAKHIR DI SINI ---

          if (_searchQuery.isNotEmpty) {
            products = products.where((product) {
              return product.name.toLowerCase().contains(_searchQuery.toLowerCase());
            }).toList();
          }

          if (products.isEmpty) {
            return const Center(
              child: Text(
                'Tidak ada produk yang cocok dengan pencarian Anda.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            );
          }

          // Tampilan GRID (default) atau LIST sesuai toggle — data sama.
          if (_isGridView) {
            return Padding(
              padding: const EdgeInsets.all(8.0),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.55,
                  crossAxisSpacing: 8.0,
                  mainAxisSpacing: 8.0,
                ),
                itemCount: products.length,
                itemBuilder: (context, index) {
                  return ProductCard(product: products[index]);
                },
              ),
            );
          }

          return ListView.builder(
            itemCount: products.length,
            itemBuilder: (context, index) {
              return ProductListCard(product: products[index]);
            },
          );
        },
      ),
    );
  }
}
