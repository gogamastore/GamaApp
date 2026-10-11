import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/data/firestore_service.dart';
import '../../home_layout/application/app_layout_provider.dart';
import '../../home_layout/domain/app_layout.dart';
import '../../home_layout/presentation/blocks/product_block.dart';
import '../../home_layout/presentation/widgets/configurable_product_card.dart';
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
    // Konfigurasi App Builder (settings/app_layout → catalog). Hanya dipakai
    // untuk tampilan GRID saat admin sudah mem-Publish; tampilan LIST tetap
    // memakai ProductListCard bawaan.
    final appLayout = context.watch<AppLayoutProvider>();
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
            // Prioritas 1: Produk dengan stok > 0 (Tersedia) diutamakan;
            // produk habis (stok 0) selalu di paling belakang.
            final aTersedia = a.stock > 0;
            final bTersedia = b.stock > 0;

            if (aTersedia && !bTersedia) {
              return -1; // a (tersedia) diletakkan sebelum b (habis).
            }
            if (!aTersedia && bTersedia) {
              return 1; // a (habis) diletakkan setelah b (tersedia).
            }

            // Prioritas 2: purchaseAt TERBARU dulu (produk yang baru
            // dibeli/restock tampil di depan). Produk tanpa purchaseAt
            // dianggap paling lama (0).
            final pa = a.purchaseAt?.millisecondsSinceEpoch ?? 0;
            final pb = b.purchaseAt?.millisecondsSinceEpoch ?? 0;
            if (pa != pb) {
              return pb.compareTo(pa); // descending
            }

            // Prioritas 3 (fallback stabil): urutkan berdasarkan nama (A-Z).
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
            // Bila admin sudah mem-Publish App Builder, grid mengikuti tipe
            // layout + gaya kartu dari konfigurasi; jika belum, pakai bawaan.
            if (appLayout.hasConfig) {
              return _buildConfiguredCatalog(
                context,
                products,
                appLayout.layout.catalog,
              );
            }
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

  /// Merender daftar katalog sesuai `CatalogConfig` (tipe layout + kartu).
  /// Grid & list dibuat lazy (builder) agar katalog panjang tetap ringan;
  /// staggered/quilted memakai [ProductLayoutView] di dalam area gulir.
  Widget _buildConfiguredCatalog(
    BuildContext context,
    List<Product> products,
    CatalogConfig catalog,
  ) {
    final style = catalog.card;
    final spacing = catalog.spacing;

    switch (catalog.layout) {
      case ProductLayout.listTile:
        return ListView.separated(
          padding: const EdgeInsets.all(8),
          itemCount: products.length,
          separatorBuilder: (_, __) => SizedBox(height: spacing),
          itemBuilder: (context, i) =>
              ProductListTileCard(product: products[i], style: style),
        );

      case ProductLayout.simpleList:
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: products.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) =>
              ProductSimpleRow(product: products[i], style: style),
        );

      case ProductLayout.staggered:
      case ProductLayout.quilted:
        // Kedua layout ini butuh tinggi semua kartu sekaligus → render penuh
        // di dalam SingleChildScrollView (jarang dipakai untuk katalog besar).
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: LayoutBuilder(
            builder: (context, cons) => ProductLayoutView(
              products: products,
              config: _toBlockConfig(catalog),
              paddingH: 8,
              fullWidth: cons.maxWidth,
            ),
          ),
        );

      case ProductLayout.grid:
      default:
        final cols = catalog.gridColumns.clamp(1, 4);
        return LayoutBuilder(
          builder: (context, cons) {
            final itemWidth =
                (cons.maxWidth - 16 - spacing * (cols - 1)) / cols;
            return GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                childAspectRatio: _gridAspect(style, itemWidth),
              ),
              itemCount: products.length,
              itemBuilder: (context, i) => ConfigurableProductCard(
                product: products[i],
                style: style,
                fillHeight: true,
                compact: itemWidth < 120,
              ),
            );
          },
        );
    }
  }

  /// Rasio lebar:tinggi tiap sel grid agar gambar + info muat tanpa overflow.
  double _gridAspect(ProductCardStyle s, double width) {
    var info = 24.0; // padding kartu
    if (s.showCategory) info += 15;
    if (s.showTitle) info += 17.0 * s.titleMaxLines;
    if (s.showStock) info += 16;
    if (s.showPrice || s.showCartButton) info += 42;
    final h = width / (s.imageRatio <= 0 ? 1 : s.imageRatio) + info;
    return width / h;
  }

  /// Membungkus [CatalogConfig] menjadi [ProductBlockConfig] agar bisa memakai
  /// ulang [ProductLayoutView] (staggered/quilted). Field data tidak relevan.
  ProductBlockConfig _toBlockConfig(CatalogConfig c) => ProductBlockConfig(
        source: 'latest',
        category: '',
        brandId: '',
        limit: 1 << 20,
        sort: 'default',
        hideOutOfStock: false,
        layout: c.layout,
        gridColumns: c.gridColumns,
        rows: 1,
        spacing: c.spacing,
        autoSlide: false,
        card: c.card,
      );
}
