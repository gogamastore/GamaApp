import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'src/core/navigation/router.dart';
import 'src/core/update/update_gate.dart';
import 'src/features/cart/application/cart_provider.dart';
import 'src/features/authentication/data/auth_service.dart';
import 'src/core/data/firestore_service.dart';
import 'src/core/theme/theme_provider.dart';
import 'src/features/profile/application/address_provider.dart';
import 'src/features/authentication/presentation/splash_screen.dart';
import 'src/features/products/application/promotion_provider.dart'; // Impor baru

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inisialisasi Firebase sekali di sini (sebelum runApp) agar Crashlytics siap.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ── Firebase Crashlytics ─────────────────────────────────────────
  // Crashlytics TIDAK didukung di Web — hanya aktifkan di platform native
  // (Android/iOS). Tanpa guard ini, build web akan crash saat startup.
  if (!kIsWeb) {
    // Aktifkan pengumpulan crash hanya pada mode rilis (hindari noise saat debug).
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);

    // Tangkap semua error Flutter (framework) → kirim ke Crashlytics.
    FlutterError.onError = (errorDetails) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
    };

    // Tangkap error asinkron yang tidak tertangani (di luar Flutter framework).
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  // Muat data locale untuk DateFormat/NumberFormat 'id_ID' (mencegah
  // LocaleDataException saat memformat tanggal/mata uang, khususnya di Web).
  await initializeDateFormatting('id_ID', null);

  runApp(const AppInitializer());
}

class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  AppInitializerState createState() => AppInitializerState();
}

class AppInitializerState extends State<AppInitializer> {
  late final Future<AuthService> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = _initializeServices();
  }

  Future<AuthService> _initializeServices() async {
    // Firebase sudah diinisialisasi di main(); di sini cukup siapkan AuthService.
    final authService = AuthService();
    await authService.isReady;
    return authService;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AuthService>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return MaterialApp(
            home: Scaffold(
              body: Center(
                child: Text('Error initializing app: ${snapshot.error}'),
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.done) {
          return MyApp(authService: snapshot.data!);
        }

        return const MaterialApp(
          home: SplashScreen(),
        );
      },
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.authService});

  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    final appRouter = AppRouter(authService);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: authService),
        Provider<FirestoreService>(create: (_) => FirestoreService()),
        // --- PENAMBAHAN PROVIDER PROMOSI ---
        ChangeNotifierProvider<PromotionProvider>(
          create: (context) => PromotionProvider(context.read<FirestoreService>()),
        ),
        ChangeNotifierProxyProvider<AuthService, CartProvider>(
          create: (context) => CartProvider(
            context.read<FirestoreService>(),
            context.read<AuthService>(),
          ),
          update: (context, auth, previousCart) =>
              previousCart ?? CartProvider(context.read<FirestoreService>(), auth),
        ),
        ChangeNotifierProxyProvider<AuthService, AddressProvider>(
          create: (context) => AddressProvider(
            firestoreService: context.read<FirestoreService>(),
            authService: context.read<AuthService>(),
          ),
          update: (context, auth, previousProvider) =>
              previousProvider ??
              AddressProvider(
                  firestoreService: context.read<FirestoreService>(),
                  authService: auth),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: appRouter.router,
        title: 'Gogama Store',
        theme: ThemeProvider.lightTheme,
        debugShowCheckedModeBanner: false,
        // Gate pemeriksa versi: paksa update bila versi terpasang sudah usang.
        builder: (context, child) =>
            UpdateGate(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
