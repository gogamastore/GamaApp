import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../domain/voucher.dart';
import '../../../core/data/firestore_service.dart';
import '../../authentication/data/auth_service.dart';
import '../../cart/application/cart_provider.dart' show CartProvider;
import '../../profile/domain/address.dart';
import '../domain/bank_account.dart';
import '../domain/shipping_option.dart';
import '../data/biteship_service.dart';
import '../data/payment_service.dart';

class DeliveryInfo {
  String recipientName;
  String phoneNumber;
  String address;
  String city;
  String postalCode;
  String specialInstructions;

  DeliveryInfo({
    this.recipientName = '',
    this.phoneNumber = '',
    this.address = '',
    this.city = '',
    this.postalCode = '',
    this.specialInstructions = '',
  });

  bool get isCompleted =>
      recipientName.isNotEmpty &&
      phoneNumber.isNotEmpty &&
      address.isNotEmpty &&
      city.isNotEmpty &&
      postalCode.isNotEmpty;
}

class CheckoutProvider with ChangeNotifier {
  final AuthService _authService;
  final FirestoreService _firestoreService;
  final CartProvider _cartProvider;

  // ── State dasar ───────────────────────────────────────────────
  bool _isInitializing = true;
  bool _isProcessingOrder = false;

  List<BankAccount> _bankAccounts = [];
  List<Address> _userAddresses = [];

  final List<ShippingOption> _shippingOptions = [
    ShippingOption(
      id: 'courier',
      name: 'Pengiriman oleh Kurir',
      price: 15000,
      estimatedDays: '1-3 hari',
      description:
          'Pengiriman menggunakan kurir, harga mulai dari Rp 15.000/koli',
    ),
    ShippingOption(
      id: 'pickup',
      name: 'Ambil di Toko',
      price: 0,
      estimatedDays: 'Hari ini',
      description: 'Ambil sendiri di toko, tidak ada biaya pengiriman',
    ),
  ];

  ShippingOption? _selectedShipping;
  String _selectedPaymentMethod = 'bank_transfer';
  Address? _selectedAddress;
  final DeliveryInfo _deliveryInfo = DeliveryInfo();
  XFile? _paymentProofImage;

  // ── Payment (Midtrans) ────────────────────────────────────────
  final PaymentService _paymentService = PaymentService();
  String? _midtransRedirectUrl;
  String? _midtransToken;
  bool _isCreatingPayment = false;
  String? _lastOrderId;

  // ── Biteship — menangani SEMUA kurir termasuk GoSend/Grab/Paxel ──
  final BiteshipService _biteshipService = BiteshipService();
  BiteshipArea? _selectedDestinationArea;
  List<BiteshipRate> _biteshipRates = [];
  BiteshipRate? _selectedBiteshipRate;
  bool _isLoadingBiteshipRates = false;
  String? _biteshipRatesError;

  // ── Voucher ───────────────────────────────────────────────────
  List<Voucher> _vouchers = [];
  Voucher? _selectedVoucher;
  Map<String, int> _voucherUsage = {}; // kode → jumlah pakai user 24 jam

  // ── Biaya Admin & Layanan (settings/admin_fees) ───────────────
  bool _feesEnabled = false;
  num _adminFeeFlat = 0;
  num _serviceFeePercent = 0;
  num _serviceFeeMax = 0;

  // ─────────────────────────────────────────────────────────────
  // Getters
  // ─────────────────────────────────────────────────────────────
  bool get isInitializing => _isInitializing;
  bool get isProcessingOrder => _isProcessingOrder;
  List<BankAccount> get bankAccounts => _bankAccounts;
  List<Address> get userAddresses => _userAddresses;
  List<ShippingOption> get shippingOptions => _shippingOptions;
  ShippingOption? get selectedShipping => _selectedShipping;
  String get selectedPaymentMethod => _selectedPaymentMethod;
  Address? get selectedAddress => _selectedAddress;
  DeliveryInfo get deliveryInfo => _deliveryInfo;
  XFile? get paymentProofImage => _paymentProofImage;

  String? get midtransRedirectUrl => _midtransRedirectUrl;
  String? get midtransToken => _midtransToken;
  bool get isCreatingPayment => _isCreatingPayment;
  String? get lastOrderId => _lastOrderId;

  BiteshipArea? get selectedDestinationArea => _selectedDestinationArea;
  List<BiteshipRate> get biteshipRates => _biteshipRates;
  BiteshipRate? get selectedBiteshipRate => _selectedBiteshipRate;
  bool get isLoadingBiteshipRates => _isLoadingBiteshipRates;
  String? get biteshipRatesError => _biteshipRatesError;

  double get subtotal => _cartProvider.total;

  /// Total berat paket (gram): berat asli produk × qty (fallback 200gr).
  /// Nilai inilah yang dikirim ke Biteship untuk menghitung tarif.
  int get totalWeightGram => _cartProvider.items.fold(
        0,
        (sum, item) => sum + (item.weightGram > 0 ? item.weightGram : 200) * item.quantity,
      );

  double get shippingCost {
    if (_selectedBiteshipRate != null) return _selectedBiteshipRate!.price;
    return _selectedShipping?.price ?? 0;
  }

  // ── Voucher ───────────────────────────────────────────────────
  List<Voucher> get vouchers => _vouchers;
  Voucher? get selectedVoucher => _selectedVoucher;

  /// Voucher yang masih dalam masa berlaku (tanggal).
  List<Voucher> get availableVouchers =>
      _vouchers.where((v) => v.isDateValid).toList();

  /// Potongan dari voucher terpilih (dihitung dari subtotal).
  double get voucherDiscount {
    final v = _selectedVoucher;
    if (v == null) return 0;
    if (subtotal < v.minPurchase) return 0;
    double d;
    if (v.discountType == 'percentage') {
      d = (subtotal * v.discountValue / 100).roundToDouble();
      if (v.maxDiscount > 0 && d > v.maxDiscount) d = v.maxDiscount.toDouble();
    } else {
      d = v.discountValue.toDouble();
    }
    return d > subtotal ? subtotal : d;
  }

  // ── Biaya admin & layanan ─────────────────────────────────────
  double get adminFee => _feesEnabled ? _adminFeeFlat.toDouble() : 0;

  double get serviceFee {
    if (!_feesEnabled || _serviceFeePercent <= 0) return 0;
    double f = (subtotal * _serviceFeePercent / 100).roundToDouble();
    if (_serviceFeeMax > 0 && f > _serviceFeeMax) f = _serviceFeeMax.toDouble();
    return f;
  }

  double get grandTotal {
    final t =
        subtotal + shippingCost - voucherDiscount + adminFee + serviceFee;
    return t < 0 ? 0 : t;
  }

  /// Alasan voucher tak bisa dipakai (null = bisa). Masa berlaku sudah
  /// disaring di [availableVouchers].
  String? voucherIneligibleReason(Voucher v) {
    if (subtotal < v.minPurchase) return 'Belanja belum memenuhi minimal';
    if (v.dailyLimitPerUser > 0 &&
        (_voucherUsage[v.code] ?? 0) >= v.dailyLimitPerUser) {
      return 'Batas ${v.dailyLimitPerUser}×/hari sudah tercapai';
    }
    return null;
  }

  void selectVoucher(Voucher v) {
    _selectedVoucher = v;
    notifyListeners();
  }

  void clearVoucher() {
    _selectedVoucher = null;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────
  // Constructor
  // ─────────────────────────────────────────────────────────────
  CheckoutProvider({
    required AuthService authService,
    required FirestoreService firestoreService,
    required CartProvider cartProvider,
  })  : _authService = authService,
        _firestoreService = firestoreService,
        _cartProvider = cartProvider;

  // ─────────────────────────────────────────────────────────────
  // Inisialisasi
  // ─────────────────────────────────────────────────────────────
  Future<void> initialize() async {
    developer.log('Initializing CheckoutProvider...', name: 'CheckoutProvider');
    _isInitializing = true;
    notifyListeners();
    _selectedShipping = _shippingOptions.first;
    await _fetchBankAccounts();
    await _fetchUserAddresses();
    await _loadVouchers();
    await _loadAdminFees();
    _isInitializing = false;
    developer.log(
      'Initialization complete. Found ${_userAddresses.length} addresses.',
      name: 'CheckoutProvider',
    );
    notifyListeners();
    _cartProvider.addListener(_onCartChanged);
  }

  void _onCartChanged() {
    if (_selectedDestinationArea != null &&
        _biteshipRates.isEmpty &&
        !_isLoadingBiteshipRates) {
      fetchBiteshipRates(
        destLat: _selectedAddress?.latitude,
        destLng: _selectedAddress?.longitude,
      );
    }
  }

  @override
  void dispose() {
    _cartProvider.removeListener(_onCartChanged);
    super.dispose();
  }

  Future<void> _fetchBankAccounts() async {
    try {
      _bankAccounts = await _firestoreService.getBankAccounts();
    } catch (e) {
      _bankAccounts = [];
      developer.log('Error fetching bank accounts',
          name: 'CheckoutProvider', error: e);
    }
  }

  Future<void> _fetchUserAddresses() async {
    final user = _authService.currentUser;
    if (user != null) {
      developer.log('Fetching addresses for user: ${user.uid}',
          name: 'CheckoutProvider');
      try {
        _userAddresses = await _firestoreService.getUserAddresses(user.uid);
        developer.log(
          'Successfully fetched ${_userAddresses.length} addresses.',
          name: 'CheckoutProvider',
        );

        Address? defaultAddress;
        try {
          defaultAddress = _userAddresses.firstWhere((a) => a.isDefault);
        } catch (_) {
          if (_userAddresses.isNotEmpty) defaultAddress = _userAddresses.first;
        }

        if (defaultAddress != null) {
          selectSavedAddress(defaultAddress);
          await _loadRatesForAddress(defaultAddress);
        }
      } catch (e, s) {
        _userAddresses = [];
        developer.log('Error fetching addresses',
            name: 'CheckoutProvider', error: e, stackTrace: s);
      }
    } else {
      developer.log('Cannot fetch addresses: User is not logged in.',
          name: 'CheckoutProvider');
      _userAddresses = [];
    }
  }

  /// Muat voucher AKTIF + hitung pemakaian user dalam 24 jam terakhir
  /// (untuk batas pakai per user per hari).
  Future<void> _loadVouchers() async {
    try {
      final db = FirebaseFirestore.instance;
      final snap = await db.collection('vouchers').get();
      _vouchers = snap.docs
          .where((d) =>
              d.data()['isActive'] == true &&
              (d.data()['code']?.toString().isNotEmpty ?? false))
          .map((d) => Voucher.fromFirestore(d))
          .toList();

      final user = _authService.currentUser;
      if (user != null) {
        final cutoff = DateTime.now().subtract(const Duration(hours: 24));
        final ordersSnap = await db
            .collection('orders')
            .where('customerId', isEqualTo: user.uid)
            .get();
        final counts = <String, int>{};
        for (final o in ordersSnap.docs) {
          final data = o.data();
          final code = data['voucherCode'];
          if (code is! String || code.isEmpty) continue;
          if ((data['status'] ?? '').toString().toLowerCase() == 'cancelled') {
            continue;
          }
          DateTime? created;
          final c = data['createdAt'];
          final dt = data['date'];
          if (c is Timestamp) {
            created = c.toDate();
          } else if (dt is Timestamp) {
            created = dt.toDate();
          }
          if (created == null || created.isBefore(cutoff)) continue;
          counts[code] = (counts[code] ?? 0) + 1;
        }
        _voucherUsage = counts;
      }
    } catch (e) {
      developer.log('Error loading vouchers',
          name: 'CheckoutProvider', error: e);
    }
  }

  /// Muat konfigurasi biaya admin & layanan (settings/admin_fees).
  Future<void> _loadAdminFees() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('settings')
          .doc('admin_fees')
          .get();
      final d = snap.data();
      if (d != null) {
        _feesEnabled = d['enabled'] != false;
        _adminFeeFlat = (d['adminFee'] as num?) ?? 0;
        _serviceFeePercent = (d['serviceFeePercent'] as num?) ?? 0;
        _serviceFeeMax = (d['serviceFeeMax'] as num?) ?? 0;
      }
    } catch (e) {
      developer.log('Error loading admin fees',
          name: 'CheckoutProvider', error: e);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Method utama: load rates untuk alamat tertentu
  //
  // FAST PATH — address.hasBiteshipArea == true:
  //   Area ID sudah ada di Firestore → skip searchArea()
  //   Langsung fetchBiteshipRates() — hanya 1 network call
  //   Ini path yang diambil di Android setelah user simpan alamat baru
  //
  // FALLBACK — belum ada biteshipDestinationAreaId (alamat lama):
  //   _searchAreaAndFetchRates() — cari area dulu via Biteship API
  // ─────────────────────────────────────────────────────────────
  Future<void> _loadRatesForAddress(Address address) async {
    developer.log(
      '_loadRatesForAddress: city=${address.city}, '
      'hasBiteshipArea=${address.hasBiteshipArea}, '
      'biteshipAreaId=${address.biteshipDestinationAreaId}, '
      'hasCoords=${address.hasCoordinates}',
      name: 'CheckoutProvider',
    );

    // ── FAST PATH ────────────────────────────────────────────────
    if (address.hasBiteshipArea) {
      developer.log(
        'FAST PATH: menggunakan area ID tersimpan → ${address.biteshipDestinationAreaId}',
        name: 'CheckoutProvider',
      );
      _selectedDestinationArea = BiteshipArea(
        id: address.biteshipDestinationAreaId!,
        name: address.biteshipDestinationAreaName ?? address.city,
        adminName: '',
        postalCode: address.postalCode,
      );
      _selectedBiteshipRate = null;
      _biteshipRates = [];
      _biteshipRatesError = null;
      notifyListeners();
      await fetchBiteshipRates(
        destLat: address.latitude,
        destLng: address.longitude,
      );
      return;
    }

    // ── FALLBACK: Area ID belum ada → search via Biteship API ────
    developer.log(
      'FALLBACK: area ID tidak ada di Firestore → searchAreaAndFetchRates',
      name: 'CheckoutProvider',
    );
    await _searchAreaAndFetchRates(
      cityQuery: address.city,
      destLat: address.latitude,
      destLng: address.longitude,
      postalCode: address.postalCode,
    );
  }

  Future<void> _searchAreaAndFetchRates({
    required String cityQuery,
    double? destLat,
    double? destLng,
    String? postalCode,
  }) async {
    final cleanCity = cityQuery
        .replaceAll(
            RegExp(r'^(Kota |Kabupaten |Kab\. |Kab |Kec\. |Kec )',
                caseSensitive: false),
            '')
        .trim();

    final queries = <String>[
      if (postalCode != null && postalCode.isNotEmpty) postalCode,
      cleanCity,
      cityQuery,
    ].where((q) => q.isNotEmpty && q.length >= 3).toList();

    BiteshipArea? foundArea;

    for (final query in queries) {
      developer.log('Mencari area Biteship: "$query"',
          name: 'CheckoutProvider');
      try {
        final areas = await _biteshipService.searchArea(query);
        developer.log('Hasil "$query": ${areas.length} area',
            name: 'CheckoutProvider');
        if (areas.isNotEmpty) {
          foundArea = areas.first;
          break;
        }
      } catch (e) {
        developer.log('Error search "$query": $e', name: 'CheckoutProvider');
      }
    }

    if (foundArea != null) {
      _selectedDestinationArea = foundArea;
      _selectedBiteshipRate = null;
      _biteshipRates = [];
      _biteshipRatesError = null;
      notifyListeners();
      await fetchBiteshipRates(destLat: destLat, destLng: destLng);
    } else {
      // Tampilkan pesan ke UI — tidak silent
      _biteshipRatesError =
          'Area pengiriman tidak ditemukan untuk "$cityQuery". '
          'Pilih area secara manual di bawah.';
      notifyListeners();
      developer.log(
        'FALLBACK FAILED: area tidak ditemukan untuk "$cityQuery"',
        name: 'CheckoutProvider',
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Methods — Shipping & Alamat
  // ─────────────────────────────────────────────────────────────
  void selectShippingOption(ShippingOption option) {
    if (_selectedShipping?.id == option.id) return;
    _selectedShipping = option;
    _selectedBiteshipRate = null;
    notifyListeners();
  }

  void selectPaymentMethod(String method) {
    if (_selectedPaymentMethod == method) return;
    _selectedPaymentMethod = method;
    notifyListeners();
  }

  void selectSavedAddress(Address address) {
    _selectedAddress = address;
    _deliveryInfo.recipientName = address.name;
    _deliveryInfo.phoneNumber = address.phone;
    _deliveryInfo.address = address.address;
    _deliveryInfo.city = address.city;
    _deliveryInfo.postalCode = address.postalCode;
    notifyListeners();
  }

  /// Dipanggil saat user memilih alamat dari dropdown checkout.
  Future<void> selectSavedAddressAndLoadRates(Address address) async {
    selectSavedAddress(address);
    _biteshipRates = [];
    _selectedBiteshipRate = null;
    _selectedDestinationArea = null;
    _biteshipRatesError = null;
    notifyListeners();
    await _loadRatesForAddress(address);
  }

  void clearSelectedAddress() {
    _selectedAddress = null;
    _deliveryInfo.recipientName = '';
    _deliveryInfo.phoneNumber = '';
    _deliveryInfo.address = '';
    _deliveryInfo.city = '';
    _deliveryInfo.postalCode = '';
    notifyListeners();
  }

  void updateDeliveryInfo({
    String? recipientName,
    String? phoneNumber,
    String? address,
    String? city,
    String? postalCode,
    String? specialInstructions,
  }) {
    _deliveryInfo.recipientName = recipientName ?? _deliveryInfo.recipientName;
    _deliveryInfo.phoneNumber = phoneNumber ?? _deliveryInfo.phoneNumber;
    _deliveryInfo.address = address ?? _deliveryInfo.address;
    _deliveryInfo.city = city ?? _deliveryInfo.city;
    _deliveryInfo.postalCode = postalCode ?? _deliveryInfo.postalCode;
    _deliveryInfo.specialInstructions =
        specialInstructions ?? _deliveryInfo.specialInstructions;
    _selectedAddress = null;
    notifyListeners();
  }

  /// Update catatan kurir TANPA menghapus alamat tersimpan yang dipilih.
  void updateSpecialInstructions(String value) {
    _deliveryInfo.specialInstructions = value;
  }

  // ─────────────────────────────────────────────────────────────
  // Methods — Biteship (semua kurir: JNE, J&T, GoSend, Grab, dll)
  // ─────────────────────────────────────────────────────────────

  /// Dipanggil saat user pilih area manual dari BiteshipAreaSearchField
  void onDestinationAreaSelected(BiteshipArea area) {
    _selectedDestinationArea = area;
    _selectedBiteshipRate = null;
    _biteshipRates = [];
    _biteshipRatesError = null;
    _selectedShipping = null;
    notifyListeners();
    fetchBiteshipRates(
      destLat: _selectedAddress?.latitude,
      destLng: _selectedAddress?.longitude,
    );
  }

  Future<void> searchAndSetBiteshipAreaFromCity(String cityName) async {
    await _searchAreaAndFetchRates(cityQuery: cityName);
  }

  /// Fetch tarif Biteship.
  /// Jika gagal, error tersimpan di [biteshipRatesError] dan tampil di UI.
  Future<void> fetchBiteshipRates({
    double? destLat,
    double? destLng,
  }) async {
    if (_selectedDestinationArea == null) {
      developer.log('fetchBiteshipRates: SKIP — selectedDestinationArea null',
          name: 'CheckoutProvider');
      return;
    }

    final lat = destLat ?? _selectedAddress?.latitude;
    final lng = destLng ?? _selectedAddress?.longitude;
    final hasCoords = lat != null && lng != null;

    developer.log(
      'fetchBiteshipRates: area=${_selectedDestinationArea!.id}, '
      'items=${_cartProvider.items.length}, hasCoords=$hasCoords',
      name: 'CheckoutProvider',
    );

    _isLoadingBiteshipRates = true;
    _biteshipRatesError = null;
    notifyListeners();

    final shipmentItems = _cartProvider.items.isNotEmpty
        ? _cartProvider.items
            .map((item) => ShipmentItem(
                  productId: item.productId,
                  name: item.nama,
                  price: item.harga,
                  quantity: item.quantity,
                  weightGram: item.weightGram > 0 ? item.weightGram : 200,
                ))
            .toList()
        : [
            const ShipmentItem(
              productId: 'default',
              name: 'Paket',
              price: 50000,
              quantity: 1,
              weightGram: 500,
            ),
          ];

    try {
      _biteshipRates = await _biteshipService.getRates(
        destinationAreaId: _selectedDestinationArea!.id,
        items: shipmentItems,
        destinationLatitude: lat,
        destinationLongitude: lng,
      );
      developer.log(
        'fetchBiteshipRates SUCCESS: ${_biteshipRates.length} layanan',
        name: 'CheckoutProvider',
      );
    } on BiteshipException catch (e) {
      // Error tersimpan di state dan ditampilkan di UI (tidak silent)
      _biteshipRatesError = '${e.message} (${e.code ?? "unknown"})';
      _biteshipRates = [];
      developer.log(
        'fetchBiteshipRates FAILED: ${e.message} [${e.code}]',
        name: 'CheckoutProvider',
      );
    } catch (e) {
      _biteshipRatesError = 'Terjadi kesalahan: $e';
      _biteshipRates = [];
      developer.log('fetchBiteshipRates UNEXPECTED: $e',
          name: 'CheckoutProvider');
    } finally {
      _isLoadingBiteshipRates = false;
      notifyListeners();
    }
  }

  /// Retry manual dari tombol di UI (untuk Android jika cold start timeout)
  Future<void> retryFetchBiteshipRates() async {
    developer.log('retryFetchBiteshipRates dipanggil',
        name: 'CheckoutProvider');
    await fetchBiteshipRates(
      destLat: _selectedAddress?.latitude,
      destLng: _selectedAddress?.longitude,
    );
  }

  void selectBiteshipRate(BiteshipRate rate) {
    _selectedBiteshipRate = rate;
    _selectedShipping = null;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────
  // Methods — Bukti bayar
  // ─────────────────────────────────────────────────────────────
  Future<void> pickPaymentProof() async {
    try {
      final XFile? image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (image != null) {
        _paymentProofImage = image;
        notifyListeners();
      }
    } catch (e) {
      developer.log('Error picking payment proof',
          name: 'CheckoutProvider', error: e);
    }
  }

  void removePaymentProof() {
    _paymentProofImage = null;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────
  // Methods — Proses order
  // ─────────────────────────────────────────────────────────────
  Future<String?> processOrder() async {
    final user = _authService.currentUser;
    if (user == null ||
        !_deliveryInfo.isCompleted ||
        _cartProvider.items.isEmpty) {
      return 'Formulir tidak lengkap atau keranjang kosong.';
    }

    _isProcessingOrder = true;
    notifyListeners();

    final String newOrderId = _firestoreService.getNewOrderId();

    try {
      final now = DateTime.now();

      String paymentProofUrl = '';
      if (_paymentProofImage != null) {
        paymentProofUrl = await _firestoreService.uploadPaymentProof(
          user.uid,
          newOrderId,
          _paymentProofImage!,
        );
      }

      String shippingMethodName = _selectedShipping?.name ?? '';
      if (_selectedBiteshipRate != null) {
        shippingMethodName =
            '${_selectedBiteshipRate!.courierName} ${_selectedBiteshipRate!.serviceName}';
      }

      final orderData = {
        // Penanda kanal penjualan: memisahkan pesanan marketplace dari
        // transaksi kasir POS (source: 'pos') di koleksi `orders` yang sama.
        'source': 'marketplace',
        'created_at': now.toUtc().toIso8601String(),
        'updated_at': now.toUtc().toIso8601String(),
        'date': now,
        'stockUpdateTimestamp': now.toUtc().toIso8601String(),
        'customer': _deliveryInfo.recipientName,
        'customerId': user.uid,
        'customerDetails': {
          'name': _deliveryInfo.recipientName,
          'address':
              '${_deliveryInfo.address}, ${_deliveryInfo.city}, ${_deliveryInfo.postalCode}',
          'whatsapp': _deliveryInfo.phoneNumber,
        },
        if (_selectedAddress?.latitude != null)
          'destinationLatitude': _selectedAddress!.latitude,
        if (_selectedAddress?.longitude != null)
          'destinationLongitude': _selectedAddress!.longitude,
        'products': _cartProvider.items
            .map((item) => {
                  'productId': item.productId,
                  'name': item.nama,
                  'price': item.harga,
                  'quantity': item.quantity,
                  'image': item.gambar,
                  'weightGram': item.weightGram > 0 ? item.weightGram : 200,
                })
            .toList(),
        'productIds': _cartProvider.items.map((e) => e.productId).toList(),
        'paymentMethod': _selectedPaymentMethod,
        'paymentStatus': _paymentProofImage != null ? 'Paid' : 'Unpaid',
        'paymentProofUrl': paymentProofUrl,
        'paymentProofFileName': _paymentProofImage?.name ?? '',
        'paymentProofId': '',
        'paymentProofUploaded': _paymentProofImage != null,
        'shippingMethod': shippingMethodName,
        'shippingFee': shippingCost,
        if (_selectedBiteshipRate != null) ...{
          'biteshipCourierCode': _selectedBiteshipRate!.courierId,
          'biteshipServiceCode': _selectedBiteshipRate!.courierServiceCode,
          'biteshipCourierName': _selectedBiteshipRate!.courierName,
          'biteshipServiceName': _selectedBiteshipRate!.serviceName,
          'destinationAreaId': _selectedDestinationArea?.id ?? '',
        },
        'subtotal': subtotal,
        'voucherCode': _selectedVoucher?.code,
        'voucherDiscount': voucherDiscount,
        'adminFee': adminFee,
        'serviceFee': serviceFee,
        'total': grandTotal,
        'status': _selectedPaymentMethod == 'cod' ? 'Processing' : 'Pending',
        'stockUpdated': true,
      };

      final itemsToUpdate = _cartProvider.items
          .map((item) =>
              {'productId': item.productId, 'quantity': item.quantity})
          .toList();

      await _firestoreService.placeOrderInTransaction(
          newOrderId, orderData, itemsToUpdate);

      _lastOrderId = newOrderId;
      await _cartProvider.clearCart();

      return null;
    } catch (e) {
      developer.log('Error processing order',
          name: 'CheckoutProvider', error: e);
      return e.toString();
    } finally {
      _isProcessingOrder = false;
      notifyListeners();
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Methods — Midtrans
  // ─────────────────────────────────────────────────────────────
  Future<String?> createMidtransPayment(String orderId) async {
    _isCreatingPayment = true;
    notifyListeners();
    try {
      final result = await _paymentService.createTransaction(orderId);
      _midtransToken = result.token;
      _midtransRedirectUrl = result.redirectUrl;
      notifyListeners();
      return null;
    } on PaymentException catch (e) {
      developer.log('createMidtransPayment error',
          name: 'CheckoutProvider', error: e.message);
      return e.message;
    } finally {
      _isCreatingPayment = false;
      notifyListeners();
    }
  }
}