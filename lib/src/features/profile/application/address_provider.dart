import 'dart:async';
import 'package:flutter/material.dart';
import 'package:myapp/src/features/authentication/data/auth_service.dart';
import '../../../core/data/firestore_service.dart';
import '../domain/address.dart';

class AddressProvider with ChangeNotifier {
  final FirestoreService _firestoreService;
  final AuthService _authService;

  List<Address> _addresses = [];
  bool _isLoading = false;
  StreamSubscription? _addressSubscription;

  List<Address> get addresses => _addresses;
  bool get isLoading => _isLoading;

  AddressProvider({
    required FirestoreService firestoreService,
    required AuthService authService,
  })  : _firestoreService = firestoreService,
        _authService = authService {
    _listenToAddresses();
  }

  void _listenToAddresses() {
    final user = _authService.currentUser;
    if (user != null) {
      _isLoading = true;
      notifyListeners();
      _addressSubscription?.cancel();
      _addressSubscription = _firestoreService.streamUserAddresses(user.uid).listen((addresses) {
        _addresses = addresses;
        _isLoading = false;
        notifyListeners();
      });
    }
  }

  Future<void> addAddress(Address address) async {
    final user = _authService.currentUser;
    if (user != null) {
      await _firestoreService.addAddress(user.uid, address);
    }
  }

  Future<void> updateAddress(Address address) async {
    final user = _authService.currentUser;
    if (user != null) {
      await _firestoreService.updateAddress(user.uid, address);
    }
  }

  Future<void> deleteAddress(String addressId) async {
    final user = _authService.currentUser;
    if (user != null) {
      await _firestoreService.deleteAddress(user.uid, addressId);
    }
  }

  @override
  void dispose() {
    _addressSubscription?.cancel();
    super.dispose();
  }
}