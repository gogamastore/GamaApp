import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/src/features/authentication/data/auth_service.dart';
import 'package:myapp/src/features/authentication/presentation/login_screen.dart';
import 'package:myapp/src/features/authentication/presentation/reseller_registration_screen.dart'; // Import baru
import 'package:myapp/src/features/authentication/presentation/splash_screen.dart';
import 'package:myapp/src/features/products/presentation/home_screen.dart';
import 'package:myapp/src/features/notifications/presentation/notifications_screen.dart';

import '../../features/cart/presentation/cart_screen.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/checkout/presentation/checkout_screen.dart';
import '../../features/checkout/presentation/payment_webview_screen.dart';
import '../../features/orders/presentation/order_history_screen.dart';
import '../../features/orders/presentation/order_detail_screen.dart';
import '../../features/orders/domain/order.dart';
import '../../features/profile/domain/address.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/profile/presentation/address_screen.dart';
import '../../features/profile/presentation/add_edit_address_screen.dart';
import '../../features/profile/presentation/contact_screen.dart';
import '../../features/profile/presentation/help_center_screen.dart';
import '../../features/products/domain/product.dart';
import '../../features/products/presentation/catalog_screen.dart';
import '../../features/products/presentation/product_detail_screen.dart';
import '../widgets/scaffold_with_nav_bar.dart';

class AppRouter {
  final AuthService authService;

  AppRouter(this.authService);

  late final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: authService,
    redirect: (BuildContext context, GoRouterState state) {
      final authStatus = authService.authStatus;
      final location = state.matchedLocation;

      if (authStatus == AuthStatus.unknown) {
        return '/splash';
      }

      final isLoggedIn = authStatus == AuthStatus.authenticated;
      // Tambahkan pengecekan untuk halaman registrasi
      final isGoingToLogin = location == '/login';
      final isGoingToRegister = location == '/register-reseller';
      final isGoingToSplash = location == '/splash';

      // Jika sudah login, jangan biarkan ke halaman login, register, atau splash
      if (isLoggedIn && (isGoingToLogin || isGoingToSplash || isGoingToRegister)) {
        return '/';
      }

      // Jika belum login dan tidak sedang menuju halaman login atau register, arahkan ke login
      if (!isLoggedIn && !isGoingToLogin && !isGoingToRegister) {
        return '/login';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return ScaffoldWithNavBar(navigationShell: navigationShell);
        },
        branches: [
          // --- Home Branch ---
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                name: 'home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          // --- Catalog Branch ---
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/catalog',
                name: 'catalog',
                builder: (context, state) => const CatalogScreen(),
              ),
            ],
          ),
          // --- Notifications Branch ---
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/notifications',
                name: 'notifications',
                builder: (context, state) => const NotificationsScreen(),
              ),
            ],
          ),
          // --- Profile Branch ---
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                name: 'profile',
                builder: (context, state) => const ProfileScreen(),
                routes: [
                  GoRoute(
                    path: 'edit',
                    name: 'editProfile',
                    builder: (context, state) => const EditProfileScreen(),
                  ),
                  GoRoute(
                    path: 'orders',
                    name: 'orderHistory',
                    builder: (context, state) => OrderHistoryScreen(
                      initialTab: state.uri.queryParameters['tab'],
                    ),
                  ),
                  GoRoute(
                    path: 'address',
                    name: 'address',
                    builder: (context, state) => const AddressScreen(),
                    routes: [
                      GoRoute(
                        path: 'add',
                        name: 'addAddress',
                        builder: (context, state) => const AddEditAddressScreen(),
                      ),
                      GoRoute(
                        path: 'edit',
                        name: 'editAddress',
                        builder: (context, state) {
                          final address = state.extra as Address?;
                          return AddEditAddressScreen(address: address);
                        },
                      ),
                    ]
                  ),
                  GoRoute(
                    path: 'contact',
                    name: 'contact',
                    builder: (context, state) => const ContactScreen(),
                  ),
                  GoRoute(
                    path: 'help',
                    name: 'help',
                    builder: (context, state) => const HelpCenterScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      // --- Top-level Routes ---
      GoRoute(
        path: '/product/:id',
        name: 'productDetail',
        builder: (context, state) {
          final product = state.extra as Product?;
          final productId = state.pathParameters['id'];
          if (product != null) {
            return ProductDetailScreen(product: product);
          } else {
            return ProductDetailScreen(productId: productId);
          }
        },
      ),
      GoRoute(
        path: '/cart',
        name: 'cart',
        builder: (context, state) => const CartScreen(),
      ),
      GoRoute(
        path: '/chat',
        name: 'chat',
        builder: (context, state) => const ChatScreen(),
      ),
      GoRoute(
        path: '/checkout',
        name: 'checkout',
        builder: (context, state) => const CheckoutScreen(),
      ),
      GoRoute(
        path: '/payment-webview',
        name: 'paymentWebView',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return PaymentWebViewScreen(
            orderId: extra['orderId'] as String,
            redirectUrl: extra['redirectUrl'] as String,
          );
        },
      ),
      GoRoute(
        path: '/order-detail',
        name: 'orderDetail',
        builder: (context, state) {
          final order = state.extra as Order;
          return OrderDetailScreen(order: order);
        },
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      // --- RUTE BARU UNTUK REGISTRASI RESELLER ---
      GoRoute(
        path: '/register-reseller',
        name: 'registerReseller',
        builder: (context, state) => const ResellerRegistrationScreen(),
      ),
    ],
  );
}
