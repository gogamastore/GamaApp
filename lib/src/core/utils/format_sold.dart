/// Ringkas jumlah terjual: 999 → "999", 1.200 → "1,2rb", 12.000 → "12rb".
String formatSold(int n) {
  final v = n < 0 ? 0 : n;
  if (v < 1000) return '$v';
  final rb = v / 1000;
  final s = rb >= 100
      ? rb.round().toString()
      : rb.toStringAsFixed(1).replaceAll('.', ',').replaceAll(RegExp(r',0$'), '');
  return '${s}rb';
}
