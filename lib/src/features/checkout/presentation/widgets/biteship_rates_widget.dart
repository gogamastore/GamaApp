import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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

  bool _isInitializing = true;
  bool _isProcessingOrder = false;

  List<BankAccount> _bankAccounts = [];
  List<Address> _userAddresses = [];

  final List<ShippingOption> _shippingOptions = [
    ShippingOption(
      id: 'pickup',
      name: 'Ambil di Toko',
      price: 0,
      estimatedDays: 'Hari ini',
      description: 'Ambil sendiri di toko, tidak ada biaya pengiriman',
    ),
  ];

  ShippingOption? _selectedShipping;
  String _selectedPaymentMethod = 'midtrans';
  Address? _selectedAddress;
  final DeliveryInfo _deliveryInfo = DeliveryInfo();
  XFile? _paymentProofImage;

  // Payment
  final PaymentService _paymentService = PaymentService();
  String? _midtransRedirectUrl;
  String? _midtransToken;
  bool _isCreatingPayment = false;
  String? _lastOrderId;

  // Biteship
  final BiteshipService _biteshipService = BiteshipService();
  BiteshipArea? _selectedDestinationArea;
  List<BiteshipRate> _biteshipRates = [];
  BiteshipRate? _selectedBiteshipRate;
  bool _isLoadingBiteshipRates = false;
  String? _biteshipRatesError;

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

  double get shippingCost {
    if (_selectedBiteshipRate != null) return _selectedBiteshipRate!.price;
    return _selectedShipping?.price ?? 0;
  }

  double get grandTotal => subtotal + shippingCost;

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
    await _fetchBankAccounts();
    await _fetchUserAddresses();
    _isInitializing = false;
    developer.log(
      'Done. ${_userAddresses.length} addresses.',
      name: 'CheckoutProvider',
    );
    notifyListeners();

    // Re-fetch rates saat cart berubah
    _cartProvider.addListener(_onCartChanged);
  }

  void _onCartChanged() {
    if (_selectedDestinationArea != null &&
        _biteshipRates.isEmpty &&
        !_isLoadingBiteshipRates) {
      fetchBiteshipRates();
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
    }
  }

  Future<void> _fetchUserAddresses() async {
    final user = _authService.currentUser;
    if (user == null) return;

    try {
      _userAddresses = await _firestoreService.getUserAddresses(user.uid);
      developer.log('Fetched ${_userAddresses.length} addresses.',
          name: 'CheckoutProvider');

      Address? defaultAddress;
      try {
        defaultAddress = _userAddresses.firstWhere((a) => a.isDefault);
      } catch (_) {
        if (_userAddresses.isNotEmpty) defaultAddress = _userAddresses.first;
      }

      if (defaultAddress != null) {
        selectSavedAddress(defaultAddress);
        // Auto-load rates untuk alamat default
        await _loadRatesForAddress(defaultAddress);
      }
    } catch (e, s) {
      _userAddresses = [];
      developer.log('Error fetching addresses',
          name: 'CheckoutProvider', error: e, stackTrace: s);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Method utama: load rates untuk alamat tertentu
  // Strategy:
  //   1. Jika ada koordinat GPS → fetch rates by coords (lebih akurat)
  //   2. Jika tidak ada → cari area ID dari kota, lalu fetch rates
  // ─────────────────────────────────────────────────────────────
  Future<void> _loadRatesForAddress(Address address) async {
    developer.log(
      '_loadRatesForAddress: city=${address.city}, '
      'postalCode=${address.postalCode}, '
      'hasCoords=${address.hasCoordinates}',
      name: 'CheckoutProvider',
    );

    await _searchAreaAndFetchRates(
      cityQuery: address.city,
      destLat: address.latitude,
      destLng: address.longitude,
      postalCode: address.postalCode,
    );
  }

  /// Cari area Biteship dan fetch rates sekaligus.
  /// Mencoba beberapa variasi nama kota sampai ada yang berhasil.
  Future<void> _searchAreaAndFetchRates({
    required String cityQuery,
    double? destLat,
    double? destLng,
    String? postalCode,
  }) async {
    // Bersihkan nama kota — hapus "Kota ", "Kabupaten ", dll
    final cleanCity = cityQuery
        .replaceAll(
            RegExp(r'^(Kota |Kabupaten |Kab\. |Kab |Kec\. |Kec )',
                caseSensitive: false),
            '')
        .trim();

    // Prioritaskan kode pos karena lebih spesifik dan akurat
    // Biteship butuh kode pos untuk dapat area ID yang tepat
    final queries = <String>[
      if (postalCode != null && postalCode.isNotEmpty)
        postalCode, // ← prioritas 1
      cleanCity, // ← prioritas 2: nama kota bersih
      cityQuery, // ← prioritas 3: nama kota asli dari Firestore
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
          developer.log('Area ditemukan: ${foundArea.name} (${foundArea.id})',
              name: 'CheckoutProvider');
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
      notifyListeners();
      await fetchBiteshipRates(
        destLat: destLat,
        destLng: destLng,
      );
    } else {
      developer.log(
        'Area tidak ditemukan untuk: "$cityQuery" / postalCode: "$postalCode". '
        'User perlu pilih manual via BiteshipAreaSearchField.',
        name: 'CheckoutProvider',
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Methods — Alamat & Pengiriman
  // ─────────────────────────────────────────────────────────────
  void selectShippingOption(ShippingOption option) {
    _selectedShipping = option;
    _selectedBiteshipRate = null;
    notifyListeners();
  }

  void selectPaymentMethod(String method) {
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
  /// Auto-load rates berdasarkan alamat yang dipilih.
  Future<void> selectSavedAddressAndLoadRates(Address address) async {
    selectSavedAddress(address);
    _biteshipRates = [];
    _selectedBiteshipRate = null;
    _selectedDestinationArea = null;
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

  // ─────────────────────────────────────────────────────────────
  // Methods — Biteship
  // ─────────────────────────────────────────────────────────────

  /// Dipanggil saat user pilih area manual dari BiteshipAreaSearchField
  void onDestinationAreaSelected(BiteshipArea area) {
    _selectedDestinationArea = area;
    _selectedBiteshipRate = null;
    _biteshipRates = [];
    _selectedShipping = null;
    notifyListeners();
    fetchBiteshipRates(
      destLat: _selectedAddress?.latitude,
      destLng: _selectedAddress?.longitude,
    );
  }

  /// Fallback: search area dari nama kota (dipanggil jika tidak ada koordinat)
  Future<void> searchAndSetBiteshipAreaFromCity(String cityName) async {
    await _searchAreaAndFetchRates(cityQuery: cityName);
  }

  /// Fetch tarif Biteship.
  /// [destLat] dan [destLng] opsional — jika ada, kurir instan ikut muncul.
  Future<void> fetchBiteshipRates({
    double? destLat,
    double? destLng,
  }) async {
    if (_selectedDestinationArea == null) return;

    // Gunakan koordinat dari parameter atau dari alamat tersimpan
    final lat = destLat ?? _selectedAddress?.latitude;
    final lng = destLng ?? _selectedAddress?.longitude;
    final hasCoords = lat != null && lng != null;

    developer.log(
      'fetchBiteshipRates: area=${_selectedDestinationArea!.id}, '
      'cartItems=${_cartProvider.items.length}, '
      'hasCoords=$hasCoords',
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
                  weightGram: 200,
                ))
            .toList()
        : [
            ShipmentItem(
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
        'Biteship rates: ${_biteshipRates.length} layanan',
        name: 'CheckoutProvider',
      );
    } on BiteshipException catch (e) {
      _biteshipRatesError = e.message;
      _biteshipRates = [];
      developer.log('Biteship error',
          name: 'CheckoutProvider', error: e.message);
    } finally {
      _isLoadingBiteshipRates = false;
      notifyListeners();
    }
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
        'total': grandTotal,
        'status': 'Pending',
        'stockUpdated': true,
      };

      final itemsToUpdate = _cartProvider.items
          .map((i) => {'productId': i.productId, 'quantity': i.quantity})
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
      return e.message;
    } finally {
      _isCreatingPayment = false;
      notifyListeners();
    }
  }
}
