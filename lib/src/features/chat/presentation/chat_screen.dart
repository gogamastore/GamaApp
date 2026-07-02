import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';

import '../../authentication/data/auth_service.dart';
import '../data/chat_service.dart';
import '../domain/chat_message.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _chatService = ChatService();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();

  File? _imageFile;
  bool _sending = false;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _userId = context.read<AuthService>().currentUser?.uid;
    if (_userId != null) {
      _chatService.markRead(_userId!, 'user');
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked != null) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  Future<void> _send() async {
    final user = context.read<AuthService>().currentUser;
    if (user == null || _sending) return;
    final text = _textController.text;
    if (text.trim().isEmpty && _imageFile == null) return;

    setState(() => _sending = true);
    try {
      String? imageUrl;
      if (_imageFile != null) {
        imageUrl = await _chatService.uploadImage(user.uid, _imageFile!);
      }
      await _chatService.sendMessage(
        userId: user.uid,
        senderId: user.uid,
        senderRole: 'user',
        text: text,
        imageUrl: imageUrl,
        userName: user.name,
        userEmail: user.email,
        userPhotoURL: user.photoURL,
      );
      _textController.clear();
      setState(() => _imageFile = null);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengirim pesan: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_userId == null) {
      return const Scaffold(
        body: Center(child: Text('Silakan login untuk mengobrol dengan admin.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat dengan Admin'),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _chatService.messagesStream(_userId!),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data ?? [];

                // Tandai dibaca bila pesan terakhir dari admin.
                if (messages.isNotEmpty &&
                    messages.last.senderRole == 'admin') {
                  _chatService.markRead(_userId!, 'user');
                }

                if (messages.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Belum ada pesan.\nSapa admin untuk mulai mengobrol.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  );
                }

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController
                        .jumpTo(_scrollController.position.maxScrollExtent);
                  }
                });

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, i) =>
                      _bubble(theme, messages[i], messages[i].senderRole == 'user'),
                );
              },
            ),
          ),
          _inputBar(theme),
        ],
      ),
    );
  }

  Widget _bubble(ThemeData theme, ChatMessage m, bool mine) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: mine ? theme.colorScheme.primary : Colors.grey[200],
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(mine ? 14 : 2),
            bottomRight: Radius.circular(mine ? 2 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (m.imageUrl != null)
              Padding(
                padding: EdgeInsets.only(bottom: m.text.isNotEmpty ? 6 : 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: m.imageUrl!,
                    width: 200,
                    fit: BoxFit.cover,
                    placeholder: (c, u) => Container(
                      width: 200,
                      height: 150,
                      color: Colors.black12,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (c, u, e) =>
                        const Icon(Icons.broken_image, color: Colors.grey),
                  ),
                ),
              ),
            if (m.text.isNotEmpty)
              Text(
                m.text,
                style: TextStyle(color: mine ? Colors.white : Colors.black87),
              ),
          ],
        ),
      ),
    );
  }

  Widget _inputBar(ThemeData theme) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border(top: BorderSide(color: Colors.grey[200]!)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_imageFile != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(_imageFile!,
                            width: 72, height: 72, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: -8,
                        right: -8,
                        child: GestureDetector(
                          onTap: () => setState(() => _imageFile = null),
                          child: const CircleAvatar(
                            radius: 11,
                            backgroundColor: Colors.red,
                            child: Icon(Icons.close,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.image_outlined),
                  onPressed: _sending ? null : _pickImage,
                ),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'Ketik pesan...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _sending
                    ? const SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : IconButton.filled(
                        icon: const Icon(Icons.send),
                        onPressed: _send,
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
