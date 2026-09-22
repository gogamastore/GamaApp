import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../domain/banner_item.dart';
import '../domain/brand.dart';
import '../../../core/data/firestore_service.dart';
import '../../../core/widgets/whatsapp_verification_popup.dart';
import '../../authentication/data/auth_service.dart';
import '../domain/product.dart';
import 'widgets/product_card.dart';
import 'widgets/promo_section.dart';

import 'widgets/banner_carousel.dart';
import 'widgets/favorite_brand_list.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Peringatan verifikasi WhatsApp hanya ditampilkan sekali per sesi beranda,
  // supaya tidak muncul berulang setiap kali tab Beranda dibuka kembali.
  bool _whatsappPopupShown = false;

  /// Tampilkan popup bila `whatsappStatus` pada dokumen user masih
  /// 'unverified'. Dipanggil setelah frame pertama selesai dibangun.
  void _maybeShowWhatsappPopup(AuthService authService) {
    if (_whatsappPopupShown) return;
    final user = authService.currentUser;
    if (user == null || user.isWhatsappVerified) return;

    _whatsappPopupShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showWhatsappVerificationPopup(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService =
        Provider.of<FirestoreService>(context, listen: false);

    // listen: true agar pengecekan ikut berjalan begitu data user selesai dimuat.
    _maybeShowWhatsappPopup(Provider.of<AuthService>(context));

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            // Banner doesn't need horizontal padding to be full-width
            StreamBuilder<List<BannerItem>>(
              stream: firestoreService.getBannersStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const SizedBox(
                    height: 150, // Placeholder height for banner
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return BannerCarousel(banners: snapshot.data!);
              },
            ),
            const SizedBox(height: 24),

            // --- FIX: Add Padding around the brand list to prevent it from being squeezed ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: StreamBuilder<List<Brand>>(
                stream: firestoreService.getBrandsStream(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(
                        child: Text('Tidak ada brand tersedia.'));
                  }
                  return FavoriteBrandList(brands: snapshot.data!);
                },
              ),
            ),
            const SizedBox(height: 32),

            // --- Promo Products Section ---
            const PromoSection(),
            const SizedBox(height: 24),

            // --- Trending Products Section ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Produk Trending',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  TextButton(
                    onPressed: () => context.go('/catalog'),
                    child: const Text('Lihat Semua'),
                  ),
                ],
              ),
            ),
            const SizedBox(
                height: 8), // Add a small space between title and list

            // Horizontal list for trending products
            StreamBuilder<List<Product>>(
              stream: firestoreService.getTrendingProductsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                      child: 
                          Text('Error fetching products: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                      child: Text('Tidak ada produk trending saat ini.'));
                }

                final trendingProducts = snapshot.data!;

                return SizedBox(
                  height: 320, // Give the horizontal list a fixed height
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0), // Add padding to the list itself
                    scrollDirection: Axis.horizontal,
                    itemCount: trendingProducts.length,
                    itemBuilder: (context, index) {
                      final product = trendingProducts[index];
                      return Container(
                        width: 200,
                        margin: EdgeInsets.only(
                            right: index == trendingProducts.length - 1
                                ? 0
                                : 12), // Add spacing between cards
                        child: ProductCard(product: product, enableHero: false),
                      );
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: ElevatedButton.icon(
                onPressed: () => context.go('/catalog'),
                icon: const Icon(Icons.storefront),
                label: const Text('Lihat Semua Produk di Katalog'),
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50), // full width
                    textStyle: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
