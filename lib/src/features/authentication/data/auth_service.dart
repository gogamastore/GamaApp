import 'dart:async';
import 'dart:developer' as developer;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../domain/app_user.dart';

enum AuthStatus {
  unknown,
  authenticated,
  unauthenticated,
}

class AuthService with ChangeNotifier {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  AppUser? _appUser;
  AuthStatus _authStatus = AuthStatus.unknown;

  // --- FIX: Add a completer to signal when the initial auth state is ready ---
  final Completer<void> _readyCompleter = Completer<void>();

  late StreamSubscription<User?> _authStateChangesSubscription;

  AuthService() {
    // Listen to auth state changes and update our own status
    _authStateChangesSubscription =
        _firebaseAuth.authStateChanges().listen(_onAuthStateChanged);
    // Check the initial user state immediately
    _onAuthStateChanged(_firebaseAuth.currentUser);
  }

  // --- FIX: Public Future to await the initial auth state ---
  Future<void> get isReady => _readyCompleter.future;

  AppUser? get currentUser => _appUser;
  AuthStatus get authStatus => _authStatus;

  Future<void> _onAuthStateChanged(User? firebaseUser) async {
    if (firebaseUser == null) {
      _appUser = null;
      _authStatus = AuthStatus.unauthenticated;
    } else {
      try {
        final docRef = _firestore.collection('user').doc(firebaseUser.uid);
        final doc = await docRef.get();
        if (doc.exists) {
          final data = doc.data() ?? {};
          // Akun dengan verificationStatus 'pending' belum boleh dianggap
          // login sampai emailnya diverifikasi. Akun lama tanpa field ini
          // dianggap sudah terverifikasi agar tidak terkunci.
          if (data['verificationStatus'] == 'pending') {
            await firebaseUser.reload();
            final refreshedUser = _firebaseAuth.currentUser;
            if (refreshedUser != null && refreshedUser.emailVerified) {
              // Email sudah diklik verifikasinya — perbarui status di
              // Firestore lalu izinkan masuk (self-healing).
              await docRef.update({'verificationStatus': 'verified'});
              _appUser = AppUser.fromFirestore(doc);
              _authStatus = AuthStatus.authenticated;
            } else {
              _appUser = null;
              _authStatus = AuthStatus.unauthenticated;
            }
          } else {
            _appUser = AppUser.fromFirestore(doc);
            _authStatus = AuthStatus.authenticated;
          }
        } else {
          _appUser = null;
          _authStatus = AuthStatus
              .unauthenticated; // User exists in Auth but not Firestore
          developer.log(
            'Firestore document for user ${firebaseUser.uid} not found.',
            name: 'AuthService',
            level: 900, // Warning
          );
        }
      } catch (e, s) {
        developer.log(
          'Error fetching user from Firestore.',
          name: 'AuthService',
          level: 1000, // Severe
          error: e,
          stackTrace: s,
        );
        // Gagal membaca Firestore (mis. jaringan sesaat putus) BUKAN berarti
        // sesi login berakhir — token Firebase masih valid. Jangan paksa
        // logout kalau pengguna sebelumnya sudah terautentikasi, agar tidak
        // "tiba-tiba keluar". Hanya perlakukan sebagai unauthenticated bila
        // memang belum pernah berhasil login di sesi ini.
        if (_appUser != null) {
          _authStatus = AuthStatus.authenticated;
        } else {
          _appUser = null;
          _authStatus = AuthStatus.unauthenticated;
        }
      }
    }

    // --- FIX: Complete the future only once when the first auth state is known ---
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.complete();
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _authStateChangesSubscription.cancel();
    super.dispose();
  }

  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  Future<User?> signInWithEmailAndPassword(
      {required String email, required String password}) async {
    try {
      final userCredential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return userCredential.user;
    } on FirebaseAuthException {
      rethrow;
    }
  }

  Future<User?> signUpWithEmailAndPassword(
      {required String email, required String password}) async {
    try {
      final userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;
      if (user != null) {
        await _firestore.collection('user').doc(user.uid).set({
          'email': user.email,
          'displayName': '', // Initially empty, to be set in profile
          'photoURL': '', // Initially empty
          'whatsapp': '', // Initially empty
          // Nomor WhatsApp belum dibuktikan aktif — pembeli wajib memasukkan
          // kode OTP di Profil Saya sebelum bisa memesan.
          'whatsappStatus': 'unverified',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      return user;
    } on FirebaseAuthException {
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }

  /// Manually refetches user data from Firestore and notifies listeners.
  Future<void> reloadUser() async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser != null) {
      await _onAuthStateChanged(firebaseUser);
    }
  }
}