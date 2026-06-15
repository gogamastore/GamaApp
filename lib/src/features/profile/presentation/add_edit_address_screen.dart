import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../application/address_provider.dart';
import '../domain/address.dart';
import '../../../core/widgets/gogama_button.dart';
import 'location_picker_screen.dart';

class AddEditAddressScreen extends StatefulWidget {
  final Address? address;
  const AddEditAddressScreen({super.key, this.address});

  @override
  State<AddEditAddressScreen> createState() => _AddEditAddressScreenState();
}

class _AddEditAddressScreenState extends State<AddEditAddressScreen> {
  final _formKey = GlobalKey<FormState>();
  late String _label, _name, _phone, _postalCode, _province;
  late bool _isDefault;
  bool _isLoading = false;

  // Controller untuk field yang bisa diisi dari Maps
  late TextEditingController _addressController;
  late TextEditingController _cityController;

  // ── Koordinat GPS ─────────────────────────────────────────────
  double? _latitude;
  double? _longitude;
  bool _locationPicked = false;

  bool get _isEditing => widget.address != null;

  @override
  void initState() {
    super.initState();
    _label      = widget.address?.label ?? '';
    _name       = widget.address?.name ?? '';
    _phone      = widget.address?.phone ?? '';
    _province   = widget.address?.province ?? '';
    _postalCode = widget.address?.postalCode ?? '';
    _isDefault  = widget.address?.isDefault ?? false;

    _addressController = TextEditingController(text: widget.address?.address ?? '');
    _cityController    = TextEditingController(text: widget.address?.city ?? '');

    // Jika edit dan sudah ada koordinat, tandai sudah dipilih
    if (widget.address?.hasCoordinates == true) {
      _latitude      = widget.address!.latitude;
      _longitude     = widget.address!.longitude;
      _locationPicked = true;
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  // ── Buka Google Maps picker ───────────────────────────────────
  Future<void> _openLocationPicker() async {
    final result = await Navigator.push<LocationPickerResult>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialLatitude: _latitude,
          initialLongitude: _longitude,
        ),
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      _latitude      = result.latitude;
      _longitude     = result.longitude;
      _locationPicked = true;

      // Isi otomatis field dari hasil reverse geocoding
      // User masih bisa edit manual setelahnya
      if (_addressController.text.isEmpty) {
        _addressController.text = result.address;
      }
      if (_cityController.text.isEmpty) {
        _cityController.text = result.city;
      }
      if (_province.isEmpty) {
        setState(() => _province = result.province);
      }
      if (_postalCode.isEmpty) {
        setState(() => _postalCode = result.postalCode);
      }
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _formKey.currentState!.save();

    // Validasi koordinat wajib diisi
    if (!_locationPicked || _latitude == null || _longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Silakan pilih lokasi di peta terlebih dahulu.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final addressProvider = context.read<AddressProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    final newAddress = Address(
      id: _isEditing ? widget.address!.id : '',
      label: _label,
      name: _name,
      phone: _phone,
      address: _addressController.text.trim(),
      city: _cityController.text.trim(),
      province: _province,
      postalCode: _postalCode,
      isDefault: _isDefault,
      latitude: _latitude,
      longitude: _longitude,
    );

    try {
      if (_isEditing) {
        await addressProvider.updateAddress(newAddress);
      } else {
        await addressProvider.addAddress(newAddress);
      }
      if (mounted) router.pop();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Gagal menyimpan alamat: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Ubah Alamat' : 'Tambah Alamat'),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [

            // ── STEP 1: Pilih Lokasi di Peta ─────────────────────
            _buildSectionLabel('Langkah 1: Tentukan Lokasi di Peta'),
            const SizedBox(height: 8),
            _buildLocationPickerCard(),
            const SizedBox(height: 24),

            // ── STEP 2: Lengkapi Data Alamat ──────────────────────
            _buildSectionLabel('Langkah 2: Lengkapi Data Alamat'),
            const SizedBox(height: 12),

            TextFormField(
              initialValue: _label,
              decoration: const InputDecoration(
                labelText: 'Label Alamat',
                hintText: 'Contoh: Rumah, Kantor',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.bookmark_outline),
              ),
              onSaved: (v) => _label = v ?? '',
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Label tidak boleh kosong' : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              initialValue: _name,
              decoration: const InputDecoration(
                labelText: 'Nama Penerima',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
              ),
              onSaved: (v) => _name = v ?? '',
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Nama tidak boleh kosong' : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              initialValue: _phone,
              decoration: const InputDecoration(
                labelText: 'Nomor Telepon / WhatsApp',
                hintText: '628xxxxxxxxxx',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              keyboardType: TextInputType.phone,
              onSaved: (v) => _phone = v ?? '',
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Nomor telepon tidak boleh kosong' : null,
            ),
            const SizedBox(height: 16),

            // Alamat lengkap — bisa diisi otomatis dari Maps
            TextFormField(
              controller: _addressController,
              decoration: InputDecoration(
                labelText: 'Alamat Lengkap',
                hintText: 'Jl. Contoh No.1, RT/RW...',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.home_outlined),
                suffixIcon: _locationPicked
                    ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                    : null,
                helperText: _locationPicked
                    ? 'Terisi otomatis dari peta — bisa diedit'
                    : null,
                helperStyle: TextStyle(color: Colors.green[700], fontSize: 11),
              ),
              maxLines: 2,
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Alamat tidak boleh kosong' : null,
            ),
            const SizedBox(height: 16),

            // Kota — bisa diisi otomatis dari Maps
            TextFormField(
              controller: _cityController,
              decoration: InputDecoration(
                labelText: 'Kota / Kabupaten',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.location_city_outlined),
                suffixIcon: _locationPicked
                    ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                    : null,
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Kota tidak boleh kosong' : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              initialValue: _province,
              decoration: InputDecoration(
                labelText: 'Provinsi',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.map_outlined),
                suffixIcon: _locationPicked && _province.isNotEmpty
                    ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                    : null,
              ),
              onSaved: (v) => _province = v ?? '',
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Provinsi tidak boleh kosong' : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              initialValue: _postalCode,
              decoration: InputDecoration(
                labelText: 'Kode Pos',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.markunread_mailbox_outlined),
                suffixIcon: _locationPicked && _postalCode.isNotEmpty
                    ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                    : null,
              ),
              keyboardType: TextInputType.number,
              onSaved: (v) => _postalCode = v ?? '',
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Kode pos tidak boleh kosong' : null,
            ),
            const SizedBox(height: 16),

            SwitchListTile(
              title: const Text('Jadikan Alamat Utama'),
              subtitle: const Text('Alamat ini akan dipilih otomatis saat checkout'),
              value: _isDefault,
              onChanged: (v) => setState(() => _isDefault = v),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 32),

            GogamaButton(
              label: 'Simpan Alamat',
              onPressed: _submit,
              isLoading: _isLoading,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 15,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildLocationPickerCard() {
    return GestureDetector(
      onTap: _openLocationPicker,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _locationPicked
              ? Colors.green.withValues(alpha: 0.05)
              : Colors.blue.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _locationPicked ? Colors.green : Colors.blue,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: (_locationPicked ? Colors.green : Colors.blue)
                    .withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _locationPicked ? Icons.where_to_vote : Icons.add_location_alt_outlined,
                color: _locationPicked ? Colors.green : Colors.blue,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _locationPicked ? 'Lokasi Dipilih ✓' : 'Pilih Lokasi di Peta',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: _locationPicked ? Colors.green[700] : Colors.blue[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_locationPicked && _latitude != null)
                    Text(
                      '${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    )
                  else
                    Text(
                      'Geser peta untuk menentukan titik koordinat pengiriman Anda',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: _locationPicked ? Colors.green : Colors.blue,
            ),
          ],
        ),
      ),
    );
  }
}
