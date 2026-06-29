import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../application/cart_provider.dart';

// Model UI-spesifik untuk item keranjang.
class CartItemUI {
  final String id;
  final String productId;
  final String nama;
  final double harga;
  final int quantity;
  final String gambar;
  final int stok;
  final int weightGram;

  CartItemUI({
    required this.id,
    required this.productId,
    required this.nama,
    required this.harga,
    required this.quantity,
    required this.gambar,
    required this.stok,
    this.weightGram = 0,
  });

  factory CartItemUI.fromMap(Map<String, dynamic> map) {
    return CartItemUI(
      id: map['id'] ?? '',
      productId: map['productId'] ?? '',
      nama: map['nama'] ?? '',
      harga: (map['harga'] as num?)?.toDouble() ?? 0.0,
      quantity: map['quantity'] as int? ?? 0,
      gambar: map['gambar'] ?? '',
      stok: map['stok'] as int? ?? 0,
      weightGram: (map['weightGram'] as num? ?? 0).toInt(),
    );
  }

  CartItemUI copyWith({
    int? quantity,
  }) {
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

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final Set<String> _outOfStockProductIds = {};
  bool _isCheckingStock = false;

  Future<void> _handleCheckout() async {
    final cart = context.read<CartProvider>();
    if (cart.items.isEmpty || _isCheckingStock) {
      return;
    }

    setState(() {
      _isCheckingStock = true;
      _outOfStockProductIds.clear();
    });

    final List<CartItemUI> outOfStockItems = [];
    final firestore = FirebaseFirestore.instance;

    try {
      for (var item in cart.items) {
        final productDoc = await firestore.collection('products').doc(item.productId).get();

        if (productDoc.exists) {
          final availableStock = productDoc.data()!['stock'] as int? ?? 0;
          if (availableStock < item.quantity) {
            outOfStockItems.add(item);
            _outOfStockProductIds.add(item.productId);
          }
        } else {
          outOfStockItems.add(item);
          _outOfStockProductIds.add(item.productId);
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memverifikasi stok: $e')),
      );
      setState(() {
        _isCheckingStock = false;
      });
      return;
    }

    setState(() {
      _isCheckingStock = false;
    });

    if (outOfStockItems.isNotEmpty) {
      final productNames = outOfStockItems.map((item) => '"${item.nama}" (stok sisa: ${item.stok})').join(', ');
      
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Stok Tidak Cukup'),
          content: Text(
            'Produk $productNames habis atau stoknya tidak mencukupi. Silakan hapus atau kurangi jumlah produk tersebut untuk melanjutkan.',
          ),
          actions: [
            TextButton(
              child: const Text('Mengerti'),
              onPressed: () => Navigator.of(ctx).pop(),
            )
          ],
        ),
      );
    } else {
      if (mounted) {
        context.push('/checkout');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Keranjang Belanja'),
      ),
      body: Builder(
        builder: (context) {
          if (cart.isLoading) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Memuat keranjang...'),
                ],
              ),
            );
          }

          if (cart.items.isEmpty) {
            return RefreshIndicator(
              onRefresh: cart.fetchCart,
              child: ListView(
                children: const [
                  SizedBox(height: 150),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('Keranjang Kosong', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                        Text('Belum ada produk di keranjang Anda'),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: cart.fetchCart,
                  child: ListView.builder(
                    itemCount: cart.items.length,
                    itemBuilder: (context, index) {
                      final item = cart.items[index];
                      final isOutOfStock = _outOfStockProductIds.contains(item.productId);
                      return _CartItemCard(key: ValueKey(item.id), item: item, isOutOfStock: isOutOfStock);
                    },
                  ),
                ),
              ),
              // --- PENAMBAHAN FUNGSI BARU DIMULAI DI SINI ---
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Produk:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                        Text(
                          '${cart.items.length} Produk',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.blueGrey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Harga:', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        Text(
                          NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ').format(cart.total),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // --- PENAMBAHAN FUNGSI BARU BERAKHIR DI SINI ---
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  onPressed: _isCheckingStock ? null : _handleCheckout,
                  child: _isCheckingStock 
                      ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white,)) 
                      : const Text('Checkout'),
                ),
              )
            ],
          );
        },
      ),
    );
  }
}

class _CartItemCard extends StatefulWidget {
  final CartItemUI item;
  final bool isOutOfStock;

  const _CartItemCard({super.key, required this.item, this.isOutOfStock = false});

  @override
  State<_CartItemCard> createState() => _CartItemCardState();
}

class _CartItemCardState extends State<_CartItemCard> {
  late final TextEditingController _quantityController;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(text: widget.item.quantity.toString());
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _CartItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item.quantity != oldWidget.item.quantity &&
        widget.item.quantity.toString() != _quantityController.text) {
      final currentSelection = _quantityController.selection;
      final newText = widget.item.quantity.toString();
      _quantityController.text = newText;
      final newOffset = currentSelection.baseOffset > newText.length ? newText.length : currentSelection.baseOffset;
      _quantityController.selection = TextSelection.collapsed(offset: newOffset);
    }
  }

  void _onQuantityChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    int newQuantity = int.tryParse(value) ?? 0;
    final stock = widget.item.stok;

    if (newQuantity > stock) {
      _quantityController.text = stock.toString();
      _quantityController.selection = TextSelection.fromPosition(TextPosition(offset: _quantityController.text.length));
      newQuantity = stock;
    }

    _debounce = Timer(const Duration(milliseconds: 800), () {
      if (newQuantity < 0) newQuantity = 0;
      if (newQuantity == 0) {
        if (mounted) context.read<CartProvider>().removeItem(widget.item.productId);
      } else {
        if (mounted) context.read<CartProvider>().updateQuantity(widget.item.productId, newQuantity);
      }
    });
  }

  void _updateByButton(int change) {
    final currentVal = int.tryParse(_quantityController.text) ?? widget.item.quantity;
    int newQuantity = currentVal + change;

    if (newQuantity > widget.item.stok) newQuantity = widget.item.stok;
    if (newQuantity <= 0) {
      context.read<CartProvider>().removeItem(widget.item.productId);
    } else {
      _quantityController.text = newQuantity.toString();
      context.read<CartProvider>().updateQuantity(widget.item.productId, newQuantity);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Card(
      color: widget.isOutOfStock ? Colors.red.withOpacity(0.1) : null,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            SizedBox(
              width: 50,
              height: 50,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: CachedNetworkImage(
                  imageUrl: item.gambar,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                  errorWidget: (context, url, error) => const Icon(Icons.broken_image, color: Colors.grey),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.nama, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ').format(item.harga), style: const TextStyle(fontSize: 12, color: Colors.deepOrange)),
                  if (widget.isOutOfStock)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text('Stok sisa: ${item.stok}', style: TextStyle(fontSize: 12, color: Colors.red[700], fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
            Row(
              children: [
                IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(), iconSize: 18.0, icon: const Icon(Icons.remove), onPressed: () => _updateByButton(-1)),
                SizedBox(
                  width: 25,
                  child: TextField(
                    controller: _quantityController,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: _onQuantityChanged,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.zero),
                  ),
                ),
                IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(), iconSize: 18.0, icon: const Icon(Icons.add), onPressed: () => _updateByButton(1)),
              ],
            ),
            IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => context.read<CartProvider>().removeItem(item.productId))
          ],
        ),
      ),
    );
  }
}
