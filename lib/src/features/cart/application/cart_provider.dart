import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/data/firestore_service.dart';
import '../../authentication/data/auth_service.dart';
import '../../flash_sale/domain/flash_sale.dart';
import '../../products/domain/product.dart';
import '../domain/cart_item.dart';
import '../presentation/cart_screen.dart'; // Using CartItemUI

/// Hasil penambahan produk ke keranjang — dipakai agar pesan ke pengguna
/// tepat (sebelumnya semua kegagalan dianggap "Keranjang Penuh").
enum AddToCartResult {
  success,
  cartFull, // sudah 160 produk unik
  insufficientStock, // total di keranjang akan melebihi stok
  notLoggedIn,
  limitedPromo, // produk promo dibatasi maks 1 pcs per pesanan
  flashLimited, // produk flash sale melebihi batas maksimal pembelian
  flashOneItem, // flash sale: hanya 1 produk per event boleh di keranjang
}

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
  Future<AddToCartResult> addItemToCart(Product product, int quantity,
      {double? discountPrice, int? maxQtyPerBuyer}) async {
    final user = _authService.currentUser;
    if (user == null) return AddToCartResult.notLoggedIn;

    // Jumlah produk ini yang SUDAH ada di keranjang.
    final int existingIndex =
        _items.indexWhere((item) => item.productId == product.id);
    final bool itemExists = existingIndex >= 0;
    final int currentQty = itemExists ? _items[existingIndex].quantity : 0;

    // Batasi jumlah PRODUK UNIK di keranjang (maks 160), sama seperti web:
    // hanya produk baru yang diblokir saat penuh — produk yang sudah ada di
    // keranjang tetap boleh diubah jumlahnya.
    if (!itemExists && _items.length >= 160) {
      return AddToCartResult.cartFull;
    }

    // AKUMULASI (bukan menimpa) — samakan dengan web: qty lama + qty baru.
    // `setCartItem` memakai set(merge:true) yang MENIMPA field quantity, jadi
    // totalnya harus dihitung di sini.
    int newQuantity = currentQty + quantity;

    // Batas 1 pcs per pesanan untuk produk promo (maxQtyPerBuyer==1).
    if (maxQtyPerBuyer != null && maxQtyPerBuyer > 0 && newQuantity > maxQtyPerBuyer) {
      newQuantity = maxQtyPerBuyer;
      // Sudah di batas & tak bisa bertambah → beri tahu pembeli, jangan tulis ulang.
      if (newQuantity <= currentQty) {
        return AddToCartResult.limitedPromo;
      }
    }

    // ── Aturan flash sale aktif (terpusat: berlaku dari jalur add mana pun) ──
    double? effectivePrice = discountPrice;
    final flash = await _firestoreService.getActiveFlashSale();
    if (flash != null && flash.flashPriceFor(product.id) != null) {
      // "Hanya 1 produk per event": tolak bila sudah ada produk flash lain.
      if (flash.oneItemPerEvent) {
        final hasOther = _items.any((it) =>
            it.productId != product.id &&
            flash.productIds.contains(it.productId));
        if (hasOther) return AddToCartResult.flashOneItem;
      }
      final cap = flash.oneItemPerEvent ? 1 : (flash.maxQtyPerBuyer ?? 0);
      if (cap > 0 && newQuantity > cap) {
        newQuantity = cap;
        if (newQuantity <= currentQty) return AddToCartResult.flashLimited;
      }
      // Harga flash menimpa harga promo/normal selama event aktif.
      effectivePrice = flash.flashPriceFor(product.id);
    }

    // Karena kini terakumulasi, stok harus divalidasi terhadap TOTAL — batas
    // di UI hanya membatasi qty yang dipilih sekali tambah.
    if (newQuantity > product.stock) {
      return AddToCartResult.insufficientStock;
    }

    final productToAdd = effectivePrice != null
        ? product.copyWith(price: effectivePrice)
        : product;

    final cartItem = CartItem(product: productToAdd, quantity: newQuantity);
    await _firestoreService.setCartItem(user.uid, cartItem);
    await fetchCart(); // Ambil ulang data keranjang untuk memperbarui UI
    return AddToCartResult.success;
  }
  // --- LOGIKA BARU BERAKHIR DI SINI ---

  /// Event flash sale yang sedang aktif (untuk validasi keranjang & checkout).
  Future<FlashSale?> activeFlashSale() => _firestoreService.getActiveFlashSale();

  Future<void> updateQuantity(String productId, int newQuantity) async {
    final user = _authService.currentUser;
    if (user == null) return;

    final itemIndex = _items.indexWhere((item) => item.productId == productId);
    if (itemIndex == -1) return;

    // Batas flash sale aktif (cap qty produk flash) — defense in depth agar
    // stepper keranjang tak bisa melewati batas, sama seperti web.
    final flash = await _firestoreService.getActiveFlashSale();
    if (flash != null && flash.flashPriceFor(productId) != null) {
      final cap = flash.oneItemPerEvent ? 1 : (flash.maxQtyPerBuyer ?? newQuantity);
      if (cap > 0 && newQuantity > cap) newQuantity = cap;
    }

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
