import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/data/firestore_service.dart';
import '../../authentication/data/auth_service.dart';
import '../../cart/application/cart_provider.dart' show CartProvider;
import '../../profile/domain/address.dart';
import '../domain/bank_account.dart';
import '../domain/shipping_option.dart';
// ── Import service pengiriman ──────────────────────────────────────
import '../data/delivery_service.dart';
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

  // ── Instant Delivery (GoSend / Grab) ─────────────────────────
  ShippingRate? _selectedInstantRate;

  // ── Biteship (JNE, J&T, SiCepat, dll) ───────────────────────
  final BiteshipService _biteshipService = BiteshipService();
  BiteshipArea? _selectedDestinationArea;
  List<BiteshipRate> _biteshipRates = [];
  BiteshipRate? _selectedBiteshipRate;
  bool _isLoadingBiteshipRates = false;
  String? _biteshipRatesError;

  // ─────────────────────────────────────────────────────────────
  // Getters — state dasar
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

  // ─────────────────────────────────────────────────────────────
  // Getters — Payment
  // ─────────────────────────────────────────────────────────────
  String? get midtransRedirectUrl => _midtransRedirectUrl;
  String? get midtransToken => _midtransToken;
  bool get isCreatingPayment => _isCreatingPayment;
  String? get lastOrderId => _lastOrderId;

  // ─────────────────────────────────────────────────────────────
  // Getters — Instant Delivery (GoSend/Grab)
  // ─────────────────────────────────────────────────────────────
  ShippingRate? get selectedInstantRate => _selectedInstantRate;

  /// Konversi selectedAddress → DeliveryLocation untuk GoSend/Grab.
  /// Mengembalikan null jika alamat belum dipilih atau belum ada koordinat GPS.
  DeliveryLocation? get selectedAddressAsDeliveryLocation {
    final addr = _selectedAddress;
    if (addr == null || !addr.hasCoordinates) return null;
    return DeliveryLocation(
      latitude: addr.latitude!,
      longitude: addr.longitude!,
      address: '${addr.address}, ${addr.city}, ${addr.province}',
      contactName: addr.name,
      contactPhone: addr.phone,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Getters — Biteship
  // ─────────────────────────────────────────────────────────────
  BiteshipArea? get selectedDestinationArea => _selectedDestinationArea;
  List<BiteshipRate> get biteshipRates => _biteshipRates;
  BiteshipRate? get selectedBiteshipRate => _selectedBiteshipRate;
  bool get isLoadingBiteshipRates => _isLoadingBiteshipRates;
  String? get biteshipRatesError => _biteshipRatesError;

  // ─────────────────────────────────────────────────────────────
  // Getters — Kalkulasi harga
  // Prioritas: Biteship → GoSend/Grab → Shipping manual
  // ─────────────────────────────────────────────────────────────
  double get subtotal => _cartProvider.total;

  double get shippingCost {
    if (_selectedBiteshipRate != null) return _selectedBiteshipRate!.price;
    if (_selectedInstantRate != null) return _selectedInstantRate!.price;
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
    _selectedShipping = _shippingOptions.first;
    await _fetchBankAccounts();
    await _fetchUserAddresses();
    _isInitializing = false;
    developer.log(
      'Initialization complete. Found ${_userAddresses.length} addresses.',
      name: 'CheckoutProvider',
    );
    notifyListeners();
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
          defaultAddress = _userAddresses.firstWhere((addr) => addr.isDefault);
        } catch (e) {
          if (_userAddresses.isNotEmpty) defaultAddress = _userAddresses.first;
        }

        if (defaultAddress != null) selectSavedAddress(defaultAddress);
      } catch (e, s) {
        _userAddresses = [];
        developer.log(
          'Error fetching user addresses',
          name: 'CheckoutProvider',
          error: e,
          stackTrace: s,
        );
      }
    } else {
      developer.log(
        'Cannot fetch addresses: User is not logged in.',
        name: 'CheckoutProvider',
      );
      _userAddresses = [];
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Methods — Shipping manual & alamat
  // ─────────────────────────────────────────────────────────────
  void selectShippingOption(ShippingOption option) {
    if (_selectedShipping?.id == option.id) return;
    _selectedShipping = option;
    // Nonaktifkan pilihan kurir instan & Biteship jika pilih manual
    _selectedInstantRate = null;
    _selectedBiteshipRate = null;
    if (option.id == 'courier' && _selectedPaymentMethod == 'cod') {
      _selectedPaymentMethod = 'bank_transfer';
    }
    notifyListeners();
  }

  void selectPaymentMethod(String method) {
    if (_selectedPaymentMethod == method) return;
    if (method == 'cod' && _selectedShipping?.id == 'courier') return;
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
    // Saat user edit manual, lepas referensi ke saved address
    _selectedAddress = null;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────
  // Methods — Instant Delivery (GoSend / Grab)
  // ─────────────────────────────────────────────────────────────

  /// Pilih tarif GoSend atau Grab. Set null untuk deselect.
  void selectInstantRate(ShippingRate? rate) {
    _selectedInstantRate = rate;
    if (rate != null) {
      // Nonaktifkan pilihan lain jika instant dipilih
      _selectedShipping = null;
      _selectedBiteshipRate = null;
    }
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────
  // Methods — Biteship (JNE, J&T, SiCepat, dll)
  // ─────────────────────────────────────────────────────────────

  /// Dipanggil saat user memilih area dari BiteshipAreaSearchField.
  void onDestinationAreaSelected(BiteshipArea area) {
    _selectedDestinationArea = area;
    _selectedBiteshipRate = null;
    _biteshipRates = [];
    notifyListeners();
    fetchBiteshipRates();
  }

  /// Fetch tarif Biteship berdasarkan area tujuan yang dipilih.
  Future<void> fetchBiteshipRates() async {
    if (_selectedDestinationArea == null || _cartProvider.items.isEmpty) return;

    _isLoadingBiteshipRates = true;
    _biteshipRatesError = null;
    notifyListeners();

    final shipmentItems = _cartProvider.items
        .map((item) => ShipmentItem(
              productId: item.productId,
              name: item.nama,
              price: item.harga,
              quantity: item.quantity,
              weightGram: 200, // default 200g per item
            ))
        .toList();

    try {
      _biteshipRates = await _biteshipService.getRates(
        destinationAreaId: _selectedDestinationArea!.id,
        items: shipmentItems,
      );
    } on BiteshipException catch (e) {
      _biteshipRatesError = e.message;
      _biteshipRates = [];
    } finally {
      _isLoadingBiteshipRates = false;
      notifyListeners();
    }
  }

  /// Dipanggil saat user memilih salah satu tarif Biteship.
  void selectBiteshipRate(BiteshipRate rate) {
    _selectedBiteshipRate = rate;
    // Nonaktifkan pilihan lain
    _selectedShipping = null;
    _selectedInstantRate = null;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────
  // Methods — Bukti bayar
  // ─────────────────────────────────────────────────────────────
  Future<void> pickPaymentProof() async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(
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
      final isoTimestamp = now.toUtc().toIso8601String();

      String paymentProofUrl = '';
      if (_paymentProofImage != null) {
        paymentProofUrl = await _firestoreService.uploadPaymentProof(
          user.uid,
          newOrderId,
          _paymentProofImage!,
        );
      }

      // Tentukan nama & kode kurir yang dipilih
      String shippingMethodName = _selectedShipping?.name ?? '';
      double shippingFee = shippingCost;

      if (_selectedBiteshipRate != null) {
        shippingMethodName =
            '${_selectedBiteshipRate!.courierName} ${_selectedBiteshipRate!.serviceName}';
      } else if (_selectedInstantRate != null) {
        shippingMethodName = _selectedInstantRate!.serviceName;
      }

      final orderData = {
        // Timestamps
        'created_at': isoTimestamp,
        'updated_at': isoTimestamp,
        'date': now,
        'stockUpdateTimestamp': isoTimestamp,

        // Customer
        'customer': _deliveryInfo.recipientName,
        'customerId': user.uid,
        'customerDetails': {
          'name': _deliveryInfo.recipientName,
          'address':
              '${_deliveryInfo.address}, ${_deliveryInfo.city}, ${_deliveryInfo.postalCode}',
          'whatsapp': _deliveryInfo.phoneNumber,
        },

        // Koordinat tujuan (untuk GoSend/Grab jika tersedia)
        if (_selectedAddress?.hasCoordinates == true) ...{
          'destinationLatitude': _selectedAddress!.latitude,
          'destinationLongitude': _selectedAddress!.longitude,
        },

        // Produk
        'products': _cartProvider.items
            .map((item) => {
                  'productId': item.productId,
                  'name': item.nama,
                  'price': item.harga,
                  'quantity': item.quantity,
                  'image': item.gambar,
                })
            .toList(),
        'productIds':
            _cartProvider.items.map((item) => item.productId).toList(),

        // Pembayaran
        'paymentMethod': _selectedPaymentMethod,
        'paymentStatus': _paymentProofImage != null ? 'Paid' : 'Unpaid',
        'paymentProofUrl': paymentProofUrl,
        'paymentProofFileName': _paymentProofImage?.name ?? '',
        'paymentProofId': '',
        'paymentProofUploaded': _paymentProofImage != null,

        // Pengiriman
        'shippingMethod': shippingMethodName,
        'shippingFee': shippingFee,

        // Biteship — diisi jika pakai JNE/J&T/dll
        if (_selectedBiteshipRate != null) ...{
          'biteshipCourierCode': _selectedBiteshipRate!.courierId,
          'biteshipServiceCode': _selectedBiteshipRate!.courierServiceCode,
          'biteshipCourierName': _selectedBiteshipRate!.courierName,
          'biteshipServiceName': _selectedBiteshipRate!.serviceName,
          'destinationAreaId': _selectedDestinationArea?.id ?? '',
        },

        // Totals
        'subtotal': subtotal,
        'total': grandTotal,

        // Status
        'status': 'Pending',
        'stockUpdated': true,
      };

      final itemsToUpdate = _cartProvider.items
          .map((item) =>
              {'productId': item.productId, 'quantity': item.quantity})
          .toList();

      await _firestoreService.placeOrderInTransaction(
          newOrderId, orderData, itemsToUpdate);

      // Simpan lastOrderId sebelum cart dikosongkan
      _lastOrderId = newOrderId;

      await _cartProvider.clearCart();

      return null; // Success
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
  // Methods — Midtrans payment
  // ─────────────────────────────────────────────────────────────

  /// Buat transaksi Midtrans Snap untuk orderId yang sudah dibuat.
  /// Mengembalikan String pesan error, atau null jika berhasil.
  Future<String?> createMidtransPayment(String orderId) async {
    _isCreatingPayment = true;
    notifyListeners();

    try {
      final result = await _paymentService.createTransaction(orderId);
      _midtransToken = result.token;
      _midtransRedirectUrl = result.redirectUrl;
      notifyListeners();
      return null; // sukses
    } on PaymentException catch (e) {
      developer.log(
        'createMidtransPayment error',
        name: 'CheckoutProvider',
        error: e.message,
      );
      return e.message;
    } finally {
      _isCreatingPayment = false;
      notifyListeners();
    }
  }
}
