import 'package:flutter/material.dart';

/// Pemetaan status pengiriman Biteship → Bahasa Indonesia, mengikuti istilah
/// pada halaman tracking Biteship. Dipakai bersama oleh detail pesanan &
/// kartu tracking agar konsisten.

bool _has(String s, List<String> keys) => keys.any(s.contains);

const _kOnTheWay = [
  'dropping_off', 'in_transit', 'on_process', 'out_for_delivery', 'on_the_way', 'delivering',
];
const _kFailed = ['cancelled', 'canceled', 'rejected', 'failed', 'not_found'];

/// Judul status dalam Bahasa Indonesia.
String biteshipStatusLabel(String? status) {
  if (status == null || status.isEmpty) return 'Memproses…';
  final s = status.toLowerCase();
  if (s.contains('confirmed')) return 'Permintaan Pengiriman Telah Diterima';
  if (_has(s, ['allocating', 'waiting'])) return 'Mencari Kurir';
  if (s.contains('allocated')) return 'Permintaan Pengiriman Telah Diterima';
  if (s.contains('picking_up') || s == 'pickup') return 'Pesanan Sedang Proses Penjemputan';
  if (s.contains('picked')) return 'Pesanan Telah Dijemput';
  if (_has(s, _kOnTheWay)) return 'Pesanan Sedang Dalam Perjalanan';
  if (s.contains('delivered')) return 'Pesanan Telah Sampai Tujuan';
  if (s.contains('hold')) return 'Pengiriman Tertunda';
  if (s.contains('return')) return 'Paket Dikembalikan';
  if (_has(s, _kFailed)) return 'Pengiriman Gagal / Dibatalkan';
  return status;
}

/// Keterangan status dalam Bahasa Indonesia (dipakai bila Biteship tidak
/// mengirim catatan).
String biteshipStatusDesc(String? status) {
  final s = status?.toLowerCase() ?? '';
  if (s.contains('confirmed')) return 'Pesanan kurir dikonfirmasi. Kurir telah diberi tahu untuk menjemput.';
  if (_has(s, ['allocating', 'waiting'])) return 'Sedang mencari kurir terdekat.';
  if (s.contains('allocated')) return 'Kurir telah dialokasikan. Menunggu dijemput.';
  if (s.contains('picking_up') || s == 'pickup') return 'Kurir sedang menuju lokasi penjemputan.';
  if (s.contains('picked')) return 'Paket telah dijemput kurir.';
  if (_has(s, _kOnTheWay)) return 'Paket sedang menuju alamat tujuan.';
  if (s.contains('delivered')) return 'Paket telah sampai di tujuan.';
  if (s.contains('hold')) return 'Pengiriman tertunda sementara.';
  if (s.contains('return')) return 'Paket dikembalikan ke pengirim.';
  if (_has(s, _kFailed)) return 'Pengiriman dibatalkan atau gagal.';
  return '';
}

/// Warna indikator status.
Color biteshipStatusColor(String? status) {
  final s = status?.toLowerCase() ?? '';
  if (s.contains('delivered')) return Colors.green;
  if (s.contains('return') || _has(s, _kFailed)) return Colors.red;
  if (_has(s, _kOnTheWay)) return Colors.blue;
  return Colors.orange;
}
