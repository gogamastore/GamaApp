import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rxdart/rxdart.dart';

import '../../features/products/domain/product.dart';
import '../../features/cart/domain/cart_item.dart';
import '../../features/orders/domain/order.dart';
import '../../features/products/domain/banner_item.dart';
import '../../features/products/domain/brand.dart';
import '../../features/checkout/domain/bank_account.dart';
import '../../features/profile/domain/address.dart';
import '../../features/products/domain/promotion.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // ... (fungsi lainnya tetap sama) ...
    Future<String> _getDownloadUrl(String gsUri) async {
    if (gsUri.startsWith('gs://')) {
      try {
        final ref = _storage.refFromURL(gsUri);
        return await ref.getDownloadURL();
      } catch (e) {
        developer.log('Error getting download URL for $gsUri', name: 'FirestoreService', error: e);
        return ''; 
      }
    }
    return gsUri;
  }

  Future<Product> _transformProduct(Product product) async {
    final imageUrl = await _getDownloadUrl(product.imageUrl);
    // Pakai copyWith agar SEMUA field (termasuk weightGram & sku) tetap terbawa;
    // hanya imageUrl yang di-resolve menjadi download URL.
    return product.copyWith(imageUrl: imageUrl);
  }
  
  Future<Brand> _transformBrand(Brand brand) async {
    final logoUrl = await _getDownloadUrl(brand.logoUrl);
    return Brand(
      name: brand.name,
      logoUrl: logoUrl,
    );
  }

  Stream<List<BannerItem>> getBannersStream() {
    return _db
        .collection('banners')
        .where('isActive', isEqualTo: true)
        .orderBy('order')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => BannerItem.fromMap(doc.data())).toList());
  }

  Stream<List<Brand>> getBrandsStream() {
    return _db
        .collection('brands')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Brand.fromMap(doc.data())).toList())
        .asyncMap((brands) => Future.wait(brands.map(_transformBrand)));
  }

  Stream<List<Product>> getProductsStream() {
    return _db.collection('products').orderBy('name').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Product.fromFirestore(doc)).toList();
    }).asyncMap((products) => Future.wait(products.map(_transformProduct)));
  }

  Stream<List<Product>> getTrendingProductsStream() {
    return _db.collection('trending_products').snapshots().switchMap((snapshot) {
      final productIds = snapshot.docs.map((doc) => doc['productId'] as String).toList();

      if (productIds.isEmpty) {
        return Stream.value([]);
      }

      final productStreams = productIds.map((id) {
        return _db.collection('products').doc(id).snapshots().asyncMap((doc) async {
          if (!doc.exists) return null;
          final product = Product.fromFirestore(doc);
          return await _transformProduct(product);
        });
      });

      return CombineLatestStream.list(productStreams)
          .map((products) => products.where((p) => p != null).cast<Product>().toList());
    });
  }

  Stream<List<PromoProduct>> getPromoProductsStream() {
    final now = DateTime.now();
    return _db
        .collection('promotions')
        .where('startDate', isLessThanOrEqualTo: now)
        .where('endDate', isGreaterThanOrEqualTo: now)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Promotion.fromFirestore(doc)).toList())
        .switchMap((promotions) {
      if (promotions.isEmpty) {
        return Stream.value([]);
      }

      final promoProductStreams = promotions.map((promo) {
        return _db.collection('products').doc(promo.productId).snapshots().transform(
          StreamTransformer.fromHandlers(
            handleData: (doc, sink) async {
              if (doc.exists) {
                final rawProductData = doc.data() as Map<String, dynamic>; // Ambil data mentah untuk log
                final product = Product.fromFirestore(doc);

                // --- PERANGKAP DAN KARANTINA DATA NaN ---
                bool isCorrupt = false;
                String corruptionDetails = '';

                if (product.price.isNaN) {
                  isCorrupt = true;
                  corruptionDetails += 'product.price is NaN. ';
                }
                if (product.stock.isNaN) {
                    isCorrupt = true;
                    corruptionDetails += 'product.stock is NaN. ';
                }
                if (promo.discountPrice.isNaN) {
                  isCorrupt = true;
                  corruptionDetails += 'promo.discountPrice is NaN. ';
                }

                if (isCorrupt) {
                  developer.log(
                    '[DATA KORUP DITEMUKAN & DIKARANTINA] Data produk atau promosi mengandung NaN. Aplikasi tetap berjalan, namun data ini tidak akan ditampilkan. Harap perbaiki data di Firestore.',
                    name: 'FirestoreService.CorruptionTrap',
                    error: 'Detail: $corruptionDetails\nID Produk: ${product.id}\nID Promo: ${promo.id}\nData Mentah Produk: $rawProductData',
                  );
                  sink.add(null); // Karantina/buang data rusak agar tidak membuat crash
                } else {
                  // Jika data bersih, lanjutkan seperti biasa
                  final transformedProduct = await _transformProduct(product);
                  sink.add(PromoProduct(product: transformedProduct, promotion: promo));
                }
                // --- AKHIR DARI PERANGKAP ---

              } else {
                sink.add(null); // Produk untuk promo ini tidak ditemukan
              }
            },
            handleError: (error, stackTrace, sink) {
              developer.log(
                'Error fetching product for promotion ${promo.id}',
                name: 'FirestoreService.getPromoProductsStream',
                error: error,
                stackTrace: stackTrace,
              );
              sink.add(null); // Emit null agar stream tetap berjalan
            },
          ),
        );
      });

      return CombineLatestStream.list(promoProductStreams)
          .map((promoProducts) => promoProducts.where((p) => p != null).cast<PromoProduct>().toList());
    });
  }

  Future<Product?> getProduct(String id) async {
    final snapshot = await _db.collection('products').doc(id).get();
    if (snapshot.exists) {
      final product = Product.fromFirestore(snapshot);
      return await _transformProduct(product);
    }
    return null;
  }
  
  Stream<List<Order>> getOrdersStream(String userId) {
    return _db
        .collection('orders')
        .where('customerId', isEqualTo: userId)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Order.fromFirestore(doc)).toList());
  }

  Future<Map<String, dynamic>> getUserCart(String uid) async {
    final cartSnapshot = await _db.collection('user').doc(uid).collection('cart').get();

    if (cartSnapshot.docs.isEmpty) {
      return {'items': [], 'total': 0.0};
    }

    double total = 0;
    List<Map<String, dynamic>> items = [];

    for (var cartDoc in cartSnapshot.docs) {
      final data = cartDoc.data();
      final productId = data['product_id'] ?? cartDoc.id;
      final quantity = data['quantity'] as int;
      final itemPrice = (data['harga'] as num?)?.toDouble() ?? 0.0;

      final productDoc = await _db.collection('products').doc(productId).get();

      if (productDoc.exists) {
        final product = await _transformProduct(Product.fromFirestore(productDoc));
        total += itemPrice * quantity;
        items.add({
          'id': cartDoc.id,
          'productId': product.id,
          'nama': product.name,
          'harga': itemPrice,
          'quantity': quantity,
          'gambar': product.imageUrl,
          'stok': product.stock,
          'weightGram': product.weightGram,
        });
      }
    }
    return {'items': items, 'total': total};
  }

  Future<void> setCartItem(String uid, CartItem item) {
    final docRef = _db.collection('user').doc(uid).collection('cart').doc(item.product.id);
    return docRef.set({
      'product_id': item.product.id,
      'nama': item.product.name,
      'harga': item.product.price,
      'gambar': item.product.imageUrl,
      'quantity': item.quantity,
      'updated_at': FieldValue.serverTimestamp(), 
    }, SetOptions(merge: true));
  }

  Future<void> updateCartItemQuantity(String uid, String productId, int newQuantity) async {
    if (newQuantity < 1) {
      return removeCartItem(uid, productId);
    }
    final docRef = _db.collection('user').doc(uid).collection('cart').doc(productId);
    return docRef.update({'quantity': newQuantity});
  }

  Future<void> removeCartItem(String uid, String productId) {
    final docRef = _db.collection('user').doc(uid).collection('cart').doc(productId);
    return docRef.delete();
  }

  Future<void> clearCart(String uid) async {
    final cartCollection = _db.collection('user').doc(uid).collection('cart');
    final snapshot = await cartCollection.get();
    final batch = _db.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    return batch.commit();
  }

  String getNewOrderId() {
    return _db.collection('orders').doc().id;
  }

  Future<List<BankAccount>> getBankAccounts() async {
    final snapshot = await _db.collection('bank_accounts').get();
    return snapshot.docs.map((doc) => BankAccount.fromFirestore(doc)).toList();
  }

  Future<String> uploadPaymentProof(String uid, String orderId, XFile image) async {
    try {
      final fileExtension = image.path.split('.').last;
      final fileName = 'payment_proof_${orderId}_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      final ref = _storage.ref('payment_proofs/$uid/$fileName');
      final uploadTask = await ref.putFile(File(image.path));
      return await uploadTask.ref.getDownloadURL();
    } catch (e) {
      developer.log('Error uploading payment proof', name: 'FirestoreService', error: e);
      return '';
    }
  }

  Future<void> placeOrderInTransaction(
      String orderId, 
      Map<String, dynamic> orderData,
      List<Map<String, dynamic>> itemsToUpdate
  ) async {
    return _db.runTransaction((transaction) async {
      final orderRef = _db.collection('orders').doc(orderId);
      transaction.set(orderRef, orderData);

      for (final item in itemsToUpdate) {
        final productRef = _db.collection('products').doc(item['productId']);
        final int quantityOrdered = item['quantity'];
        transaction.update(productRef, {'stock': FieldValue.increment(-quantityOrdered)});
      }
    });
  }

  CollectionReference _userAddressesRef(String uid) => _db.collection('user').doc(uid).collection('addresses');

  Stream<List<Address>> streamUserAddresses(String uid) {
    return _userAddressesRef(uid)
        .orderBy('isDefault', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Address.fromFirestore(doc)).toList());
  }

  Future<List<Address>> getUserAddresses(String uid) async {
    final snapshot = await _userAddressesRef(uid).orderBy('isDefault', descending: true).get();
    return snapshot.docs.map((doc) => Address.fromFirestore(doc)).toList();
  }

  Future<void> addAddress(String uid, Address address) async {
    final WriteBatch batch = _db.batch();
    
    if (address.isDefault) {
      await _removeCurrentDefault(uid, batch);
    }

    final newAddressRef = _userAddressesRef(uid).doc();
    batch.set(newAddressRef, address.toMap());

    return batch.commit();
  }

  Future<void> updateAddress(String uid, Address address) async {
    final WriteBatch batch = _db.batch();

    if (address.isDefault) {
      await _removeCurrentDefault(uid, batch, currentAddressId: address.id);
    }

    final addressRef = _userAddressesRef(uid).doc(address.id);
    var data = address.toMap();
    data['updated_at'] = FieldValue.serverTimestamp();
    batch.update(addressRef, data);

    return batch.commit();
  }

  Future<void> deleteAddress(String uid, String addressId) {
    return _userAddressesRef(uid).doc(addressId).delete();
  }

  Future<void> _removeCurrentDefault(String uid, WriteBatch batch, {String? currentAddressId}) async {
    final querySnapshot = await _userAddressesRef(uid).where('isDefault', isEqualTo: true).get();
    
    for (final doc in querySnapshot.docs) {
      if (doc.id != currentAddressId) {
        batch.update(doc.reference, {'isDefault': false});
      }
    }
  }
}
