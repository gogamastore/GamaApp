import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../../profile/data/whatsapp_verification_service.dart';

class ResellerRegistrationScreen extends StatefulWidget {
  const ResellerRegistrationScreen({super.key});

  @override
  State<ResellerRegistrationScreen> createState() =>
      _ResellerRegistrationScreenState();
}

class _ResellerRegistrationScreenState
    extends State<ResellerRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _shopNameController = TextEditingController();
  final _phoneController = TextEditingController(text: '+62 ');
  final _addressController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscureText = true;

  @override
  void dispose() {
    _nameController.dispose();
    _shopNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _registerReseller() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim());

      User? user = userCredential.user;

      if (user != null) {
        // Menggunakan koleksi 'user' (singular) dan struktur data yang benar
        await FirebaseFirestore.instance.collection('user').doc(user.uid).set({
          'name': _nameController.text.trim(),
          'shopName': _shopNameController.text.trim(),
          // Nomor disimpan ternormalisasi (62xxxxxxxxxx) agar cocok dengan
          // format yang dipakai Cloud Function pengirim OTP.
          'whatsapp': normalizeWhatsappNumber(_phoneController.text),
          'address': _addressController.text.trim(),
          'email': user.email,
          'role': 'reseller',
          'photoURL': '', // Menambahkan photoURL kosong sebagai default
          'verificationStatus':
              'pending', // Berubah 'verified' setelah email diverifikasi
          // Nomor WhatsApp belum dibuktikan aktif — pembeli wajib memasukkan
          // kode OTP di Profil Saya sebelum bisa memesan.
          'whatsappStatus': 'unverified',
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Kirim email verifikasi. Selama verificationStatus masih 'pending',
        // AuthService tidak akan menganggap user ini login, sehingga router
        // tidak mungkin mengarahkan ke beranda.
        await user.sendEmailVerification();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Pendaftaran berhasil! Silakan verifikasi email Anda.',
              ),
            ),
          );
          context.go('/verify-email', extra: user.email);
        }
      }
    } on FirebaseAuthException catch (e) {
      String message;
      if (e.code == 'email-already-in-use') {
        message = 'Email ini sudah terdaftar.';
      } else if (e.code == 'weak-password') {
        message = 'Password terlalu lemah.';
      } else {
        message = 'Terjadi kesalahan pendaftaran.';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Terjadi kesalahan yang tidak terduga.')),
        );
      }
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pendaftaran Reseller'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nama Lengkap'),
                validator: (value) =>
                    value!.isEmpty ? 'Nama tidak boleh kosong' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _shopNameController,
                decoration: const InputDecoration(labelText: 'Nama Toko'),
                validator: (value) =>
                    value!.isEmpty ? 'Nama toko tidak boleh kosong' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Nomor Telepon'),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null ||
                      value.trim() == '+62' ||
                      value.trim().length < 10) {
                    return 'Masukkan nomor telepon yang valid';
                  }
                  if (!value.startsWith('+62')) {
                    return 'Nomor harus diawali dengan +62';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: 'Alamat Lengkap'),
                maxLines: 3,
                validator: (value) =>
                    value!.isEmpty ? 'Alamat tidak boleh kosong' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty || !value.contains('@')) {
                    return 'Masukkan email yang valid';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscureText,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureText ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscureText = !_obscureText),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.length < 6) {
                    return 'Password minimal 6 karakter';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: _registerReseller,
                      child: const Text('Daftar Sekarang'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}