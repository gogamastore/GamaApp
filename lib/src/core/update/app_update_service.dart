import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Hasil pengecekan versi aplikasi terhadap konfigurasi di Firestore.
class AppUpdateInfo {
  final bool updateAvailable;
  final bool forceUpdate;
  final String currentVersion; // contoh: "1.1.1+2"
  final String latestVersion; // contoh: "2.1.1+2"
  final String updateUrl;
  final String releaseNotes;

  const AppUpdateInfo({
    required this.updateAvailable,
    required this.forceUpdate,
    required this.currentVersion,
    required this.latestVersion,
    required this.updateUrl,
    required this.releaseNotes,
  });

  const AppUpdateInfo.none()
      : updateAvailable = false,
        forceUpdate = false,
        currentVersion = '',
        latestVersion = '',
        updateUrl = '',
        releaseNotes = '';
}

/// Service untuk membaca versi aplikasi saat ini (package_info) dan
/// membandingkannya dengan versi terbaru yang tersimpan di Firestore.
///
/// Struktur dokumen Firestore yang diharapkan:
///   collection: app_config
///   document:   version
///   fields:
///     latestVersion: "2.1.1+2"   (String, format major.minor.patch+build)
///     forceUpdate:   true         (bool — paksa update bila versi lebih lama)
///     updateUrl:     "https://play.google.com/store/apps/details?id=Store.gallery.pos"
///     releaseNotes:  "..."        (String, opsional)
class AppUpdateService {
  final FirebaseFirestore _db;

  AppUpdateService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  /// Bandingkan dua versi "major.minor.patch+build".
  /// Return < 0 jika [a] < [b], 0 jika sama, > 0 jika [a] > [b].
  static int compareVersions(String a, String b) {
    List<int> parse(String v) {
      final plus = v.trim().split('+');
      final core = plus[0]
          .split('.')
          .map((e) => int.tryParse(e.trim()) ?? 0)
          .toList();
      while (core.length < 3) {
        core.add(0);
      }
      final build = plus.length > 1 ? (int.tryParse(plus[1].trim()) ?? 0) : 0;
      return [core[0], core[1], core[2], build];
    }

    final pa = parse(a);
    final pb = parse(b);
    for (var i = 0; i < 4; i++) {
      if (pa[i] != pb[i]) return pa[i] - pb[i];
    }
    return 0;
  }

  /// Versi aplikasi yang terpasang saat ini, format "major.minor.patch+build".
  Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  }

  /// Cek apakah ada pembaruan. Tidak pernah melempar — bila gagal,
  /// mengembalikan [AppUpdateInfo.none] agar aplikasi tidak terblokir.
  Future<AppUpdateInfo> checkForUpdate() async {
    try {
      final current = await currentVersion();

      final doc = await _db.collection('app_config').doc('version').get();
      if (!doc.exists) return const AppUpdateInfo.none();

      final data = doc.data() ?? {};
      final latest = (data['latestVersion'] as String?)?.trim() ?? '';
      if (latest.isEmpty) return const AppUpdateInfo.none();

      final isOlder = compareVersions(current, latest) < 0;
      final forceFlag = data['forceUpdate'] as bool? ?? false;

      return AppUpdateInfo(
        updateAvailable: isOlder,
        forceUpdate: isOlder && forceFlag,
        currentVersion: current,
        latestVersion: latest,
        updateUrl: (data['updateUrl'] as String?)?.trim() ?? '',
        releaseNotes: (data['releaseNotes'] as String?)?.trim() ?? '',
      );
    } catch (e, s) {
      developer.log('Gagal memeriksa versi aplikasi',
          name: 'AppUpdateService', error: e, stackTrace: s);
      return const AppUpdateInfo.none();
    }
  }
}
