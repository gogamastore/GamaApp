import 'package:flutter/material.dart';

/// Struktur desain aplikasi yang dapat diedit dari web admin (halaman
/// Pengaturan → App Builder) dan disimpan di Firestore `settings/app_layout`.
///
/// PENTING: skema & nilai default di file ini harus tetap sama dengan
/// `Gallery-POS-Web/src/components/app-builder/schema.ts`. Semua parser di
/// sini toleran — field yang hilang/salah tipe jatuh ke nilai default supaya
/// aplikasi tidak crash meskipun dokumen diedit manual.

/// Parse warna hex ("#RRGGBB" / "#AARRGGBB" / "RRGGBB"). String kosong atau
/// tidak valid → [fallback].
Color? parseHexColor(dynamic value, [Color? fallback]) {
  if (value is! String) return fallback;
  var hex = value.trim().replaceFirst('#', '');
  if (hex.isEmpty) return fallback;
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return fallback;
  final parsed = int.tryParse(hex, radix: 16);
  return parsed == null ? fallback : Color(parsed);
}

/// Pembungkus Map konfigurasi dengan getter bertipe + fallback default.
class ConfigMap {
  final Map<String, dynamic> raw;

  const ConfigMap(this.raw);

  factory ConfigMap.from(dynamic value) => ConfigMap(
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{});

  double number(String key, double fallback) {
    final v = raw[key];
    if (v is num && v.isFinite) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  int integer(String key, int fallback) => number(key, fallback.toDouble()).round();

  String string(String key, String fallback) {
    final v = raw[key];
    return v is String ? v : fallback;
  }

  bool boolean(String key, bool fallback) {
    final v = raw[key];
    return v is bool ? v : fallback;
  }

  Color? color(String key, [Color? fallback]) => parseHexColor(raw[key], fallback);

  ConfigMap child(String key) => ConfigMap.from(raw[key]);

  /// Daftar sub-konfigurasi (mis. `items` pada blok kategori gaya gambar).
  /// Elemen non-map diabaikan.
  List<ConfigMap> list(String key) {
    final v = raw[key];
    if (v is! List) return const [];
    return v.whereType<Map>().map(ConfigMap.from).toList();
  }

  /// Daftar nilai String (mis. `order` untuk urutan induk kategori).
  List<String> stringList(String key) {
    final v = raw[key];
    if (v is! List) return const [];
    return v.whereType<String>().toList();
  }
}

/// Mengurutkan [items] sesuai daftar id [order]. Id yang tidak ada di [order]
/// diletakkan setelahnya dengan urutan aslinya — sehingga item baru tetap muncul
/// tanpa admin harus menambahkannya ke urutan.
List<T> orderByIds<T>(List<T> items, String Function(T) idOf, List<String> order) {
  if (order.isEmpty) return items;
  final byId = {for (final it in items) idOf(it): it};
  final used = <String>{};
  final result = <T>[];
  for (final id in order) {
    final it = byId[id];
    if (it != null && used.add(id)) result.add(it);
  }
  for (final it in items) {
    if (!used.contains(idOf(it))) result.add(it);
  }
  return result;
}

// ─────────────────────────────────────────────────────────────────────────
// Desain global (tema)
// ─────────────────────────────────────────────────────────────────────────

class AppDesign {
  final String appTitle;
  final String logoUrl;
  final bool showLogo;
  final bool centerTitle;
  final Color seedColor;
  final Color appBarColor;
  final Color appBarTextColor;
  final Color buttonColor;
  final Color backgroundColor;
  final Color? priceColor; // null → colorScheme.primary
  final Color? navSelectedColor; // null → colorScheme.primary
  final String fontFamily;

  const AppDesign({
    required this.appTitle,
    required this.logoUrl,
    required this.showLogo,
    required this.centerTitle,
    required this.seedColor,
    required this.appBarColor,
    required this.appBarTextColor,
    required this.buttonColor,
    required this.backgroundColor,
    required this.priceColor,
    required this.navSelectedColor,
    required this.fontFamily,
  });

  // Nilai default = tampilan aplikasi sebelum fitur App Builder ada.
  static const defaults = AppDesign(
    appTitle: 'Manafidh Store',
    logoUrl: '',
    showLogo: false,
    centerTitle: false,
    seedColor: Color(0xFF2196F3),
    appBarColor: Color(0xFFFC4AA9),
    appBarTextColor: Colors.white,
    buttonColor: Color(0xFFFF5FB4),
    backgroundColor: Color(0xFFF5F5F7),
    priceColor: null,
    navSelectedColor: null,
    fontFamily: 'Poppins',
  );

  factory AppDesign.fromMap(dynamic value) {
    final c = ConfigMap.from(value);
    const d = defaults;
    final title = c.string('appTitle', d.appTitle).trim();
    final font = c.string('fontFamily', d.fontFamily).trim();
    return AppDesign(
      appTitle: title.isEmpty ? d.appTitle : title,
      logoUrl: c.string('logoUrl', d.logoUrl).trim(),
      showLogo: c.boolean('showLogo', d.showLogo),
      centerTitle: c.boolean('centerTitle', d.centerTitle),
      seedColor: c.color('seedColor', d.seedColor)!,
      appBarColor: c.color('appBarColor', d.appBarColor)!,
      appBarTextColor: c.color('appBarTextColor', d.appBarTextColor)!,
      buttonColor: c.color('buttonColor', d.buttonColor)!,
      backgroundColor: c.color('backgroundColor', d.backgroundColor)!,
      priceColor: c.color('priceColor'),
      navSelectedColor: c.color('navSelectedColor'),
      fontFamily: font.isEmpty ? d.fontFamily : font,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Blok halaman beranda
// ─────────────────────────────────────────────────────────────────────────

/// Jenis blok yang dikenali aplikasi. Blok dengan tipe lain diabaikan
/// (aman bila web admin menambah tipe baru sebelum aplikasi di-update).
class HomeBlockType {
  static const banner = 'banner';
  static const brands = 'brands';
  static const categories = 'categories';
  static const parentCategories = 'parentCategories';
  static const products = 'products';
  static const search = 'search';
  static const text = 'text';
  static const image = 'image';
  static const spacer = 'spacer';
  static const button = 'button';

  static const all = {
    banner, brands, categories, parentCategories, products, search, text, image, spacer, button,
  };
}

/// Gaya pembungkus yang berlaku untuk semua jenis blok.
class BlockStyle {
  final double marginTop;
  final double marginBottom;
  final double marginH;
  final double paddingH;
  final double paddingV;
  final Color? bgColor;
  final String bgImageUrl;
  final double radius;

  const BlockStyle({
    this.marginTop = 0,
    this.marginBottom = 0,
    this.marginH = 0,
    this.paddingH = 0,
    this.paddingV = 0,
    this.bgColor,
    this.bgImageUrl = '',
    this.radius = 0,
  });

  factory BlockStyle.fromMap(dynamic value) {
    final c = ConfigMap.from(value);
    return BlockStyle(
      marginTop: c.number('marginTop', 0),
      marginBottom: c.number('marginBottom', 0),
      marginH: c.number('marginH', 0),
      paddingH: c.number('paddingH', 0),
      paddingV: c.number('paddingV', 0),
      bgColor: c.color('bgColor'),
      bgImageUrl: c.string('bgImageUrl', '').trim(),
      radius: c.number('radius', 0),
    );
  }
}

class HomeBlock {
  final String id;
  final String type;
  final bool enabled;
  final String title;
  final bool showSeeAll;
  final BlockStyle style;
  final ConfigMap config;

  const HomeBlock({
    required this.id,
    required this.type,
    this.enabled = true,
    this.title = '',
    this.showSeeAll = false,
    this.style = const BlockStyle(),
    this.config = const ConfigMap({}),
  });

  factory HomeBlock.fromMap(Map<String, dynamic> map, int index) {
    final c = ConfigMap(map);
    return HomeBlock(
      id: c.string('id', 'block-$index'),
      type: c.string('type', ''),
      enabled: c.boolean('enabled', true),
      title: c.string('title', ''),
      showSeeAll: c.boolean('showSeeAll', false),
      style: BlockStyle.fromMap(map['style']),
      config: ConfigMap.from(map['config']),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Konfigurasi blok produk
// ─────────────────────────────────────────────────────────────────────────

class ProductLayout {
  static const twoColumn = 'twoColumn';
  static const threeColumn = 'threeColumn';
  static const fourColumn = 'fourColumn';
  static const grid = 'grid';
  static const staggered = 'staggered';
  static const listTile = 'listTile';
  static const simpleList = 'simpleList';
  static const largeCard = 'largeCard';
  static const carousel = 'carousel';
  static const quilted = 'quilted';
}

class ProductCardStyle {
  final String design; // card | glass | simpleCard | flat | flatSimple
  final double radius;
  final double imageRatio; // lebar / tinggi
  final BoxFit imageFit;
  final bool imageRounded;
  final bool showTitle;
  final int titleMaxLines;
  final bool showCategory;
  final bool showPrice;
  final bool showStock;
  final bool showDiscountBadge;
  final bool showCartButton;
  final Color? cardColor;
  final bool shadowEnabled;
  final double shadowBlur;
  final double shadowOffsetX;
  final double shadowOffsetY;
  final double shadowOpacity;

  const ProductCardStyle({
    required this.design,
    required this.radius,
    required this.imageRatio,
    required this.imageFit,
    required this.imageRounded,
    required this.showTitle,
    required this.titleMaxLines,
    required this.showCategory,
    required this.showPrice,
    required this.showStock,
    required this.showDiscountBadge,
    required this.showCartButton,
    required this.cardColor,
    required this.shadowEnabled,
    required this.shadowBlur,
    required this.shadowOffsetX,
    required this.shadowOffsetY,
    required this.shadowOpacity,
  });

  /// Default = sama dengan hasil `fromMap` atas Map kosong (lihat nilai di bawah).
  static const defaults = ProductCardStyle(
    design: 'card',
    radius: 12,
    imageRatio: 1.0,
    imageFit: BoxFit.cover,
    imageRounded: false,
    showTitle: true,
    titleMaxLines: 2,
    showCategory: true,
    showPrice: true,
    showStock: true,
    showDiscountBadge: true,
    showCartButton: false,
    cardColor: null,
    shadowEnabled: true,
    shadowBlur: 8,
    shadowOffsetX: 0,
    shadowOffsetY: 2,
    shadowOpacity: 0.12,
  );

  factory ProductCardStyle.fromMap(ConfigMap c) {
    return ProductCardStyle(
      design: c.string('design', 'card'),
      radius: c.number('radius', 12).clamp(0, 60).toDouble(),
      imageRatio: c.number('imageRatio', 1.0).clamp(0.4, 2.5).toDouble(),
      imageFit:
          c.string('imageFit', 'cover') == 'contain' ? BoxFit.contain : BoxFit.cover,
      imageRounded: c.boolean('imageRounded', false),
      showTitle: c.boolean('showTitle', true),
      titleMaxLines: c.integer('titleMaxLines', 2).clamp(1, 4),
      showCategory: c.boolean('showCategory', true),
      showPrice: c.boolean('showPrice', true),
      showStock: c.boolean('showStock', true),
      showDiscountBadge: c.boolean('showDiscountBadge', true),
      showCartButton: c.boolean('showCartButton', false),
      cardColor: c.color('cardColor'),
      shadowEnabled: c.boolean('shadowEnabled', true),
      shadowBlur: c.number('shadowBlur', 8).clamp(0, 40).toDouble(),
      shadowOffsetX: c.number('shadowOffsetX', 0).clamp(-20, 20).toDouble(),
      shadowOffsetY: c.number('shadowOffsetY', 2).clamp(-20, 20).toDouble(),
      shadowOpacity: c.number('shadowOpacity', 0.12).clamp(0, 1).toDouble(),
    );
  }

  List<BoxShadow>? get boxShadow => shadowEnabled
      ? [
          BoxShadow(
            color: Colors.black.withValues(alpha: shadowOpacity),
            blurRadius: shadowBlur,
            offset: Offset(shadowOffsetX, shadowOffsetY),
          ),
        ]
      : null;
}

class ProductBlockConfig {
  final String source; // trending | promo | latest | category | brand
  final String category;
  final String brandId;
  final int limit;
  final String sort; // default | priceAsc | priceDesc | nameAsc | stockDesc
  final bool hideOutOfStock;
  final String layout;
  final int gridColumns;
  final int rows;
  final double spacing;
  final bool autoSlide;
  final ProductCardStyle card;

  const ProductBlockConfig({
    required this.source,
    required this.category,
    required this.brandId,
    required this.limit,
    required this.sort,
    required this.hideOutOfStock,
    required this.layout,
    required this.gridColumns,
    required this.rows,
    required this.spacing,
    required this.autoSlide,
    required this.card,
  });

  factory ProductBlockConfig.fromConfig(ConfigMap c) {
    return ProductBlockConfig(
      source: c.string('source', 'latest'),
      category: c.string('category', ''),
      brandId: c.string('brandId', ''),
      limit: c.integer('limit', 10).clamp(1, 50),
      sort: c.string('sort', 'default'),
      hideOutOfStock: c.boolean('hideOutOfStock', false),
      layout: c.string('layout', ProductLayout.twoColumn),
      gridColumns: c.integer('gridColumns', 2).clamp(1, 4),
      rows: c.integer('rows', 1).clamp(1, 3),
      spacing: c.number('spacing', 8).clamp(0, 32).toDouble(),
      autoSlide: c.boolean('autoSlide', false),
      card: ProductCardStyle.fromMap(c.child('card')),
    );
  }

  /// Kunci yang menentukan query Firestore; bila berubah stream dibuat ulang.
  String get queryKey => '$source|$category|$brandId|$limit|$hideOutOfStock';
}

// ─────────────────────────────────────────────────────────────────────────
// Konfigurasi halaman Katalog (hanya tipe layout + kartu produk)
// ─────────────────────────────────────────────────────────────────────────

/// Mengikuti `CatalogConfig` di web `schema.ts`. Hanya mengatur tipe layout
/// (gulir vertikal) + gaya kartu produk; tanpa sumber data / kategori / tombol.
class CatalogConfig {
  final String layout; // grid | staggered | listTile | simpleList | quilted
  final int gridColumns;
  final double spacing;
  final ProductCardStyle card;

  const CatalogConfig({
    required this.layout,
    required this.gridColumns,
    required this.spacing,
    required this.card,
  });

  /// Layout yang masuk akal untuk halaman katalog (subset vertikal).
  static const validLayouts = {
    ProductLayout.grid,
    ProductLayout.staggered,
    ProductLayout.listTile,
    ProductLayout.simpleList,
    ProductLayout.quilted,
  };

  static const defaults = CatalogConfig(
    layout: ProductLayout.grid,
    gridColumns: 2,
    spacing: 8,
    card: ProductCardStyle.defaults,
  );

  factory CatalogConfig.fromConfig(ConfigMap c) {
    var layout = c.string('layout', ProductLayout.grid);
    if (!validLayouts.contains(layout)) layout = ProductLayout.grid;
    return CatalogConfig(
      layout: layout,
      gridColumns: c.integer('gridColumns', 2).clamp(1, 4),
      spacing: c.number('spacing', 8).clamp(0, 32).toDouble(),
      card: ProductCardStyle.fromMap(c.child('card')),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Layout lengkap
// ─────────────────────────────────────────────────────────────────────────

class AppLayout {
  final AppDesign design;
  final List<HomeBlock> blocks;
  final CatalogConfig catalog;

  const AppLayout({
    required this.design,
    required this.blocks,
    this.catalog = CatalogConfig.defaults,
  });

  factory AppLayout.fromMap(Map<String, dynamic>? map) {
    if (map == null) return AppLayout.defaults();
    final rawBlocks = map['blocks'];
    final blocks = <HomeBlock>[];
    if (rawBlocks is List) {
      for (var i = 0; i < rawBlocks.length; i++) {
        final b = rawBlocks[i];
        if (b is! Map) continue;
        final block = HomeBlock.fromMap(Map<String, dynamic>.from(b), i);
        if (HomeBlockType.all.contains(block.type)) blocks.add(block);
      }
    }
    return AppLayout(
      design: AppDesign.fromMap(map['design']),
      // Dokumen ada tapi tanpa field blocks → pakai susunan default.
      blocks: rawBlocks is List ? blocks : AppLayout.defaults().blocks,
      catalog: CatalogConfig.fromConfig(ConfigMap.from(map['catalog'])),
    );
  }

  /// Susunan default, meniru beranda sebelum App Builder ada.
  factory AppLayout.defaults() {
    return const AppLayout(
      catalog: CatalogConfig.defaults,
      design: AppDesign.defaults,
      blocks: [
        HomeBlock(
          id: 'banner-1',
          type: HomeBlockType.banner,
          style: BlockStyle(marginTop: 16),
        ),
        HomeBlock(
          id: 'brands-1',
          type: HomeBlockType.brands,
          title: 'Brand Favoritmu',
          style: BlockStyle(marginTop: 24, paddingH: 16),
        ),
        HomeBlock(
          id: 'promo-1',
          type: HomeBlockType.products,
          title: 'Flash Sale',
          style: BlockStyle(marginTop: 24, paddingH: 16),
          config: ConfigMap({
            'source': 'promo',
            'layout': ProductLayout.grid,
            'gridColumns': 3,
            'limit': 12,
          }),
        ),
        HomeBlock(
          id: 'trending-1',
          type: HomeBlockType.products,
          title: 'Produk Trending',
          showSeeAll: true,
          style: BlockStyle(marginTop: 24, paddingH: 16),
          config: ConfigMap({
            'source': 'trending',
            'layout': ProductLayout.twoColumn,
            'limit': 10,
          }),
        ),
        HomeBlock(
          id: 'button-1',
          type: HomeBlockType.button,
          style: BlockStyle(marginTop: 24, marginBottom: 24, paddingH: 16),
          config: ConfigMap({
            'label': 'Lihat Semua Produk di Katalog',
            'link': '/catalog',
          }),
        ),
      ],
    );
  }
}
