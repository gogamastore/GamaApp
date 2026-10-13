import 'package:flutter/material.dart';

import '../domain/app_layout.dart';
import 'blocks/content_blocks.dart';
import 'blocks/product_block.dart';

/// Merender satu blok beranda sesuai tipenya.
class HomeBlockView extends StatelessWidget {
  final HomeBlock block;

  const HomeBlockView({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    return switch (block.type) {
      HomeBlockType.banner => BannerBlockView(block: block),
      HomeBlockType.brands => BrandsBlockView(block: block),
      HomeBlockType.categories => CategoriesBlockView(block: block),
      HomeBlockType.parentCategories => ParentCategoriesBlockView(block: block),
      HomeBlockType.products => ProductBlockView(block: block),
      HomeBlockType.search => SearchBlockView(block: block),
      HomeBlockType.text => TextBlockView(block: block),
      HomeBlockType.image => ImageBlockView(block: block),
      HomeBlockType.spacer => SpacerBlockView(block: block),
      HomeBlockType.button => ButtonBlockView(block: block),
      _ => const SizedBox.shrink(),
    };
  }
}
