import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/banner_item.dart';

class BannerCarousel extends StatefulWidget {
  final List<BannerItem> banners;
  final double height;
  final double viewportFraction;
  final double itemMarginH;
  final double radius;

  /// Jeda auto-slide dalam detik; 0 = nonaktif.
  final int autoplaySeconds;
  final bool showIndicator;
  final bool showText;
  final ValueChanged<BannerItem>? onTap;

  const BannerCarousel({
    super.key,
    required this.banners,
    this.height = 200,
    this.viewportFraction = 1.0,
    this.itemMarginH = 8,
    this.radius = 15,
    this.autoplaySeconds = 6,
    this.showIndicator = true,
    this.showText = true,
    this.onTap,
  });

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  int _currentPage = 0;
  late PageController _pageController;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: _currentPage,
      viewportFraction: widget.viewportFraction,
    );
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant BannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewportFraction != widget.viewportFraction) {
      final old = _pageController;
      _pageController = PageController(
        initialPage: widget.banners.isEmpty
            ? 0
            : _currentPage.clamp(0, widget.banners.length - 1),
        viewportFraction: widget.viewportFraction,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    if (oldWidget.autoplaySeconds != widget.autoplaySeconds ||
        oldWidget.banners.length != widget.banners.length) {
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = null;
    if (widget.banners.length < 2 || widget.autoplaySeconds <= 0) return;

    _timer = Timer.periodic(Duration(seconds: widget.autoplaySeconds), (timer) {
      if (!_pageController.hasClients) return;
      int nextPage = (_pageController.page ?? 0).round() + 1;
      if (nextPage >= widget.banners.length) {
        nextPage = 0;
      }
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: widget.height,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.banners.length,
            onPageChanged: (value) {
              setState(() {
                _currentPage = value;
              });
            },
            itemBuilder: (context, index) {
              final banner = widget.banners[index];
              return Card(
                clipBehavior: Clip.antiAlias,
                margin: EdgeInsets.symmetric(horizontal: widget.itemMarginH),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(widget.radius)),
                child: InkWell(
                  onTap: widget.onTap == null ? null : () => widget.onTap!(banner),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // --- IMPROVEMENT: Added loading and error builders for robustness ---
                      Image.network(
                        banner.imageUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                  : null,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey[200],
                            child: const Center(
                              child: Icon(
                                Icons.broken_image,
                                size: 60,
                                color: Colors.grey,
                              ),
                            ),
                          );
                        },
                      ),
                      if (widget.showText) ...[
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.black.withValues(alpha: 0.6),
                                Colors.transparent
                              ],
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 16,
                          left: 16,
                          right: 16,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                banner.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                banner.subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.showIndicator) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.banners.length, (index) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 4.0),
                height: 8.0,
                width: _currentPage == index ? 24.0 : 8.0,
                decoration: BoxDecoration(
                  color: _currentPage == index
                      ? Theme.of(context).primaryColor
                      : Colors.grey,
                  borderRadius: BorderRadius.circular(12),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}
