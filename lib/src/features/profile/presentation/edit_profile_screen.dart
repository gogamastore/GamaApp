import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../../authentication/data/auth_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  EditProfileScreenState createState() => EditProfileScreenState();
}

class EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _whatsappController;

  File? _imageFile;
  final ImagePicker _picker = ImagePicker();

  bool _isLoading = false;
  bool _isDirty = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthService>().currentUser;
    _nameController = TextEditingController(text: user?.name ?? '');
    _whatsappController = TextEditingController(text: user?.whatsapp.replaceFirst('62', '') ?? '');

    _nameController.addListener(_markDirty);
    _whatsappController.addListener(_markDirty);
  }

  void _markDirty() {
    if (!_isDirty) {
      setState(() {
        _isDirty = true;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _whatsappController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
        _isDirty = true;
      });
    }
  }

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Pilih dari Galeri'),
              onTap: () async {
                await _pickImage(ImageSource.gallery);
                if (!mounted) return;
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Ambil dengan Kamera'),
              onTap: () async {
                await _pickImage(ImageSource.camera);
                if (!mounted) return;
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }


  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate() || !_isDirty) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authService = context.read<AuthService>();
      final user = authService.currentUser;
      if (user == null) return;

      String? photoURL;
      if (_imageFile != null) {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('profile_pictures')
            .child('${user.uid}.jpg');
        await storageRef.putFile(_imageFile!);
        photoURL = await storageRef.getDownloadURL();
      }

      final Map<String, dynamic> updatedData = {};
      if (_nameController.text.trim() != user.name) {
        // Field 'name' — konsisten dengan AppUser.fromFirestore & halaman web.
        updatedData['name'] = _nameController.text.trim();
      }
      final newWhatsapp = '62${_whatsappController.text.trim()}';
      if (newWhatsapp != user.whatsapp) {
        updatedData['whatsapp'] = newWhatsapp;
      }
      if (photoURL != null && photoURL != user.photoURL) {
        updatedData['photoURL'] = photoURL;
      }

      if (updatedData.isNotEmpty) {
         await FirebaseFirestore.instance
            .collection('user')
            .doc(user.uid)
            .update(updatedData);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil berhasil diperbarui!')),
      );
      
      await authService.reloadUser();
      
      if (!mounted) return;
      Navigator.of(context).pop();

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan profil: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Pengguna tidak ditemukan.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan Profil'),
        actions: [
          _isLoading
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : TextButton(
                  onPressed: _isDirty ? _saveProfile : null,
                  child: Text('Simpan', style: TextStyle(color: _isDirty ? const Color.fromARGB(255, 255, 255, 255) : Colors.grey)),
                ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Center(
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _showImagePickerOptions,
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 50,
                              backgroundColor: Colors.grey[200],
                              backgroundImage: _imageFile != null
                                  ? FileImage(_imageFile!)
                                  : (user.photoURL.isNotEmpty
                                      ? NetworkImage(user.photoURL)
                                      : null) as ImageProvider?,
                              child: _imageFile == null && user.photoURL.isEmpty
                                  ? const Icon(Icons.person, size: 50, color: Colors.grey)
                                  : null,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.blue, width: 2),
                                ),
                                child: const Icon(Icons.camera_alt, color: Colors.blue, size: 22),
                              ),
                            )
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('Foto Profil', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text('Gunakan foto yang jelas dan profesional', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nama Lengkap *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value!.isEmpty ? 'Nama tidak boleh kosong' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: user.email,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Email *',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFFf0f0f0),
                    suffixIcon: Tooltip(message: 'Email tidak dapat diubah', child: Icon(Icons.info_outline, color: Colors.grey)),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _whatsappController,
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp *',
                    prefixText: '+62 ',
                    border: OutlineInputBorder(),
                    hintText: '8123456789',
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Nomor WhatsApp tidak boleh kosong';
                    }
                    if (!RegExp(r'^\d{9,13}$').hasMatch(value)) {
                      return 'Format nomor tidak valid';
                    }
                    return null;
                  },
                ),
                 const Padding(
                  padding: EdgeInsets.only(top: 8.0, left: 12.0),
                  child: Text(
                    'Gunakan format: 8xxx (tanpa spasi atau tanda hubung)',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
