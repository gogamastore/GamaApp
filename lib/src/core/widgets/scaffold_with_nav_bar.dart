import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../features/authentication/data/auth_service.dart';
import '../../features/cart/application/cart_provider.dart';
import '../../features/chat/data/chat_service.dart';
import '../../features/notifications/data/order_notification_service.dart';

class ScaffoldWithNavBar extends StatelessWidget {
  const ScaffoldWithNavBar({
    super.key,
    required this.navigationShell,
  });
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gogama Store'),
        actions: const [
          _CartIconButton(),
          _ChatIconButton(),
        ],
      ),
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Beranda',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shop),
            label: 'Katalog',
          ),
          BottomNavigationBarItem(
            icon: _NotifTabIcon(),
            label: 'Notifikasi',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
        currentIndex: navigationShell.currentIndex,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey, // Make unselected items clearer
        type: BottomNavigationBarType.fixed, // Prevent items from shifting
        onTap: (int index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
      ),
    );
  }
}

/// Ikon tab Notifikasi dengan badge jumlah pesanan yang belum dilihat.
class _NotifTabIcon extends StatelessWidget {
  const _NotifTabIcon();

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthService>().currentUser?.uid;
    const icon = Icon(Icons.notifications_outlined);
    if (uid == null) return icon;

    return StreamBuilder<int>(
      stream: OrderNotificationService().unseenCountStream(uid),
      builder: (context, snapshot) {
        final unseen = snapshot.data ?? 0;
        if (unseen == 0) return icon;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            icon,
            Positioned(
              right: -6,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  unseen > 9 ? '9+' : '$unseen',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Ikon keranjang di app bar dengan badge jumlah produk (productId) di keranjang.
class _CartIconButton extends StatelessWidget {
  const _CartIconButton();

  @override
  Widget build(BuildContext context) {
    final count = context.watch<CartProvider>().items.length;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.shopping_cart),
          tooltip: 'Keranjang',
          onPressed: () => context.push('/cart'),
        ),
        if (count > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Ikon chat di app bar dengan badge jumlah pesan belum dibaca dari admin.
class _ChatIconButton extends StatelessWidget {
  const _ChatIconButton();

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthService>().currentUser?.uid;

    final iconButton = IconButton(
      icon: const Icon(Icons.chat_bubble_outline),
      tooltip: 'Chat dengan Admin',
      onPressed: () => context.push('/chat'),
    );

    if (uid == null) return iconButton;

    return StreamBuilder<int>(
      stream: ChatService().unreadStream(uid),
      builder: (context, snapshot) {
        final unread = snapshot.data ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            iconButton,
            if (unread > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    unread > 9 ? '9+' : '$unread',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
