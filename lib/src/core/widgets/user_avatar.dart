import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Avatar pengguna yang tahan gagal-muat: bila foto tidak ada, gagal dimuat,
/// atau koneksi lambat/timeout, menampilkan logo lokal sebagai pengganti.
/// (Menghindari error 404/timeout bocor ke Crashlytics dari NetworkImage.)
class UserAvatar extends StatelessWidget {
  final String? photoUrl;
  final double radius;

  const UserAvatar({super.key, this.photoUrl, this.radius = 40});

  static const _asset = 'assets/images/logo.png';

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;

    Widget fallback() => Image.asset(
          _asset,
          width: size,
          height: size,
          fit: BoxFit.cover,
        );

    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;

    final Widget content = hasPhoto
        ? CachedNetworkImage(
            imageUrl: photoUrl!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            placeholder: (context, url) => fallback(),
            errorWidget: (context, url, error) => fallback(),
          )
        : fallback();

    return ClipOval(
      child: SizedBox(width: size, height: size, child: content),
    );
  }
}
