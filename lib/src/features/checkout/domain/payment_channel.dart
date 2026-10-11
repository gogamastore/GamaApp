/// Katalog channel pembayaran Midtrans + helper konfigurasi. MIRROR dari
/// web `Gallery-POS-Web/src/lib/payment-channels.ts`. `code` = nilai
/// `enabled_payments` Midtrans Snap. OVO tidak punya channel Snap khusus →
/// diarahkan ke QRIS (`other_qris`).
library;

enum PaymentCategory { bank, ewallet, qris }

extension PaymentCategoryX on PaymentCategory {
  /// Kunci yang sama dengan field `fees` di settings/payment_methods.
  String get key => switch (this) {
        PaymentCategory.bank => 'bank',
        PaymentCategory.ewallet => 'ewallet',
        PaymentCategory.qris => 'qris',
      };

  String get label => switch (this) {
        PaymentCategory.bank => 'Transfer Bank',
        PaymentCategory.ewallet => 'E-wallet',
        PaymentCategory.qris => 'QRIS',
      };
}

class PaymentChannel {
  final String id;
  final PaymentCategory category;
  final String name;

  /// Kode Midtrans untuk `enabled_payments`.
  final String code;

  /// Default aktif bila belum ada konfigurasi tersimpan.
  final bool defaultEnabled;

  const PaymentChannel({
    required this.id,
    required this.category,
    required this.name,
    required this.code,
    required this.defaultEnabled,
  });
}

const kPaymentChannels = <PaymentChannel>[
  // ── Transfer Bank (Virtual Account / Bill) ──
  PaymentChannel(id: 'bca_va', category: PaymentCategory.bank, name: 'BCA', code: 'bca_va', defaultEnabled: false),
  PaymentChannel(id: 'bni_va', category: PaymentCategory.bank, name: 'BNI', code: 'bni_va', defaultEnabled: true),
  PaymentChannel(id: 'bri_va', category: PaymentCategory.bank, name: 'BRI', code: 'bri_va', defaultEnabled: true),
  PaymentChannel(id: 'mandiri', category: PaymentCategory.bank, name: 'Bank Mandiri', code: 'echannel', defaultEnabled: true),
  PaymentChannel(id: 'permata_va', category: PaymentCategory.bank, name: 'PermataBank', code: 'permata_va', defaultEnabled: true),
  PaymentChannel(id: 'cimb_va', category: PaymentCategory.bank, name: 'CIMB Niaga', code: 'cimb_va', defaultEnabled: true),
  PaymentChannel(id: 'bsi_va', category: PaymentCategory.bank, name: 'BSI', code: 'bsi_va', defaultEnabled: true),
  PaymentChannel(id: 'other_va', category: PaymentCategory.bank, name: 'Bank Lainnya', code: 'other_va', defaultEnabled: false),
  // ── E-wallet ──
  PaymentChannel(id: 'gopay', category: PaymentCategory.ewallet, name: 'GoPay', code: 'gopay', defaultEnabled: true),
  PaymentChannel(id: 'shopeepay', category: PaymentCategory.ewallet, name: 'ShopeePay', code: 'shopeepay', defaultEnabled: true),
  // OVO lewat QRIS Midtrans.
  PaymentChannel(id: 'ovo', category: PaymentCategory.ewallet, name: 'OVO', code: 'other_qris', defaultEnabled: true),
  // ── QRIS ──
  PaymentChannel(id: 'qris', category: PaymentCategory.qris, name: 'QRIS', code: 'other_qris', defaultEnabled: true),
];
