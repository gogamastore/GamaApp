import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/data/firestore_service.dart';
import '../../authentication/data/auth_service.dart';
import '../../products/domain/product.dart';
import '../domain/cart_item.dart';
import '../presentation/cart_screen.dart'; // Using CartItemUI

class CartProvider with ChangeNotifier {
  final FirestoreService _firestoreService;
  final AuthService _authService;

  CartProvider(this._firestoreService, this._authService) {
    _authService.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  bool _isLoading = false;
  List<CartItemUI> _items = [];
  double _total = 0.0;

  bool get isLoading => _isLoading;
  List<CartItemUI> get items => _items;
  double get total => _total;

  void _onAuthChanged() {
    if (_authService.currentUser != null) {
      fetchCart();
    } else {
      _clearCartData();
    }
  }

  Future<void> fetchCart() async {
    final user = _authService.currentUser;
    if (user == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final cartData = await _firestoreService.getUserCart(user.uid);
      _items = (cartData['items'] as List)
          .map((itemData) => CartItemUI.fromMap(itemData))
          .toList();
      _calculateTotal(); // Use a separate method for calculation
    } catch (e) {
      _items = [];
      _total = 0.0;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- LOGIKA BARU DIMULAI DI SINI ---
  Future<bool> addItemToCart(Product product, int quantity,
      {double? discountPrice}) async {
    final user = _authService.currentUser;
    if (user == null) return false;

    // Batasi jumlah item di keranjang
    if (_items.length >= 160) {
      return false; // Kembalikan false jika keranjang penuh
    }

    final productToAdd = discountPrice != null
        ? product.copyWith(price: discountPrice)
        : product;

    final cartItem = CartItem(product: productToAdd, quantity: quantity);
    await _firestoreService.setCartItem(user.uid, cartItem);
    await fetchCart(); // Ambil ulang data keranjang untuk memperbarui UI
    return true; // Kembalikan true jika berhasil
  }
  // --- LOGIKA BARU BERAKHIR DI SINI ---

  Future<void> updateQuantity(String productId, int newQuantity) async {
    final user = _authService.currentUser;
    if (user == null) return;

    final itemIndex = _items.indexWhere((item) => item.productId == productId);
    if (itemIndex == -1) return;

    final oldQuantity = _items[itemIndex].quantity;

    _items[itemIndex] = _items[itemIndex].copyWith(quantity: newQuantity);
    _calculateTotal();
    notifyListeners();

    try {
      await _firestoreService.updateCartItemQuantity(
          user.uid, productId, newQuantity);
    } catch (e) {
      _items[itemIndex] = _items[itemIndex].copyWith(quantity: oldQuantity);
      _calculateTotal();
      notifyListeners();
    }
  }

  Future<void> removeItem(String productId) async {
    final user = _authService.currentUser;
    if (user == null) return;

    final itemIndex = _items.indexWhere((item) => item.productId == productId);
    if (itemIndex == -1) return;

    final removedItem = _items[itemIndex];
    _items.removeAt(itemIndex);
    _calculateTotal();
    notifyListeners();

    try {
      await _firestoreService.removeCartItem(user.uid, productId);
    } catch (e) {
      _items.insert(itemIndex, removedItem);
      _calculateTotal();
      notifyListeners();
    }
  }

  Future<void> clearCart() async {
    final user = _authService.currentUser;
    if (user == null) return;

    await _firestoreService.clearCart(user.uid);
    _clearCartData();
  }

  void _calculateTotal() {
    _total =
        _items.fold(0.0, (sum, item) => sum + (item.harga * item.quantity));
  }

  void _clearCartData() {
    _items = [];
    _total = 0.0;
    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _authService.removeListener(_onAuthChanged);
    super.dispose();
  }
}

extension CartItemUICopyWith on CartItemUI {
  CartItemUI copyWith({int? quantity}) {
    return CartItemUI(
      id: id,
      productId: productId,
      nama: nama,
      harga: harga,
      quantity: quantity ?? this.quantity,
      gambar: gambar,
      stok: stok,
      weightGram: weightGram,
    );
  }
}
