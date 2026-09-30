import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../authentication/data/auth_service.dart';
import '../application/address_provider.dart';
import '../domain/address.dart';
import '../../../core/widgets/gogama_button.dart';
import '../../checkout/data/biteship_service.dart';
import '../../checkout/presentation/widgets/biteship_rates_widget.dart';
import 'location_picker_screen.dart';

class AddEditAddressScreen extends StatefulWidget {
  final Address? address;
  const AddEditAddressScreen({super.key, this.address});

  @override
  State<AddEditAddressScreen> createState() => _AddEditAddressScreenState();
}

class _AddEditAddressScreenState extends State<AddEditAddressScreen> {
  final _formKey = GlobalKey<FormState>();
  late bool _isDefault;
  bool _isLoading = false;

  // Semua field teks pakai controller agar nilainya PASTI tersimpan dan tidak
  // hilang saat form rebuild (mis. setelah kembali dari peta) — sebelumnya
  // label/nama pakai initialValue+onSaved sehingga label bisa hilang.
  late TextEditingController _labelController;
  late TextEditingController _nameController;
  late TextEditingController _addressController;
  late TextEditingController _cityController;
  late TextEditingController _phoneController;
  late TextEditingController _provinceController;
  late TextEditingController _postalCodeController;

  // ── Koordinat GPS ─────────────────────────────────────────────
  double? _latitude;
  double? _longitude;
  bool _locationPicked = false;

  // ── Biteship area destination ─────────────────────────────────
  // Disimpan ke Firestore agar checkout skip searchArea()
  BiteshipArea? _selectedBiteshipArea;

  bool get _isEditing => widget.address != null;

  @override
  void initState() {
    super.initState();

    // Default Nama Penerima & WhatsApp diambil dari profil reseller (bisa diedit).
    final profile = context.read<AuthService>().currentUser;
    final profileName = profile?.name ?? '';
    final profileWa = profile?.whatsapp ?? '';
    final defaultName =
        (profileName.isNotEmpty && profileName != 'Nama Tidak Ditemukan')
            ? profileName
            : '';
    final defaultWa =
        (profileWa.isNotEmpty && profileWa != 'Nomor Tidak Ditemukan')
            ? profileWa
            : '62';

    _isDefault = widget.address?.isDefault ?? false;

    _labelController = TextEditingController(text: widget.address?.label ?? '');
    _nameController =
        TextEditingController(text: widget.address?.name ?? defaultName);
    _addressController =
        TextEditingController(text: widget.address?.address ?? '');
    _cityController = TextEditingController(text: widget.address?.city ?? '');
    _provinceController =
        TextEditingController(text: widget.address?.province ?? '');
    _postalCodeController =
        TextEditingController(text: widget.address?.postalCode ?? '');
    // Nomor baru pakai WhatsApp profil (fallback "62"); edit pakai nilai lama.
    _phoneController = TextEditingController(
      text: widget.address?.phone.isNotEmpty == true
          ? widget.address!.phone
          : defaultWa,
    );

    // Jika edit dan sudah ada koordinat, tandai sudah dipilih
    if (widget.address?.hasCoordinates == true) {
      _latitude = widget.address!.latitude;
      _longitude = widget.address!.longitude;
      _locationPicked = true;
    }

    // Jika edit dan sudah ada area Biteship, restore pilihan sebelumnya
    if (widget.address?.hasBiteshipArea == true) {
      _selectedBiteshipArea = BiteshipArea(
        id: widget.address!.biteshipDestinationAreaId!,
        name: widget.address!.biteshipDestinationAreaName ?? '',
        adminName: '',
        postalCode: widget.address!.postalCode,
      );
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _phoneController.dispose();
    _provinceController.dispose();
    _postalCodeController.dispose();
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
      _latitude = result.latitude;
      _longitude = result.longitude;
      _locationPicked = true;

      // Isi otomatis field dari hasil reverse geocoding (bisa diedit manual).
      // Alamat & kota: isi bila masih kosong. Provinsi & kode pos: selalu
      // ikuti hasil peta bila tersedia (sama seperti perilaku halaman web).
      if (_addressController.text.isEmpty) {
        _addressController.text = result.address;
      }
      if (_cityController.text.isEmpty) {
        _cityController.text = result.city;
      }
      if (result.province.isNotEmpty) {
        _provinceController.text = result.province;
      }
      if (result.postalCode.isNotEmpty) {
        _postalCodeController.text = result.postalCode;
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
    final navigator = Navigator.of(context);

    final newAddress = Address(
      id: _isEditing ? widget.address!.id : '',
      label: _labelController.text.trim(),
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      address: _addressController.text.trim(),
      city: _cityController.text.trim(),
      province: _provinceController.text.trim(),
      postalCode: _postalCodeController.text.trim(),
      isDefault: _isDefault,
      latitude: _latitude,
      longitude: _longitude,
      // ── Simpan area Biteship ke Firestore ──────────────────
      // Checkout akan skip searchArea() dan langsung fetchRates()
      biteshipDestinationAreaId: _selectedBiteshipArea?.id,
      biteshipDestinationAreaName: _selectedBiteshipArea?.name,
    );

    try {
      if (_isEditing) {
        await addressProvider.updateAddress(newAddress);
      } else {
        await addressProvider.addAddress(newAddress);
      }
      // pop(true) → penanda "alamat tersimpan" untuk pemanggil (mis. checkout
      // yang lalu mengarahkan ke keranjang).
      if (mounted) navigator.pop(true);
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

  // ── Section label helper ──────────────────────────────────────
  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 14,
        color: Colors.black87,
      ),
    );
  }

  // ── Card pilih lokasi peta ────────────────────────────────────
  Widget _buildLocationPickerCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _locationPicked ? Colors.green : Colors.orange,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _locationPicked ? Icons.check_circle : Icons.map_outlined,
                  color: _locationPicked ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _locationPicked
                        ? 'Lokasi sudah ditentukan'
                        : 'Belum ada lokasi — wajib diisi',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _locationPicked ? Colors.green : Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            if (_locationPicked && _latitude != null) ...[
              const SizedBox(height: 4),
              Text(
                'Lat: ${_latitude!.toStringAsFixed(6)}, '
                'Lng: ${_longitude!.toStringAsFixed(6)}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.pin_drop_outlined),
                label: Text(_locationPicked
                    ? 'Ubah Lokasi di Peta'
                    : 'Pilih Lokasi di Peta'),
                onPressed: _openLocationPicker,
              ),
            ),
          ],
        ),
      ),
    );
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
              controller: _labelController,
              decoration: const InputDecoration(
                labelText: 'Label Alamat',
                hintText: 'Contoh: Rumah, Kantor',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.bookmark_outline),
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Label tidak boleh kosong' : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nama Penerima',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Nama tidak boleh kosong' : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Nomor Telepon / WhatsApp',
                hintText: '628xxxxxxxxxx',
                helperText: 'Awali dengan 62 (kode negara Indonesia)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              keyboardType: TextInputType.phone,
              validator: (v) {
                if (v == null || v.isEmpty) {
                  return 'Nomor telepon tidak boleh kosong';
                }
                if (!v.startsWith('62')) {
                  return 'Nomor harus diawali dengan 62 (contoh: 628123456789)';
                }
                if (v.length < 10) {
                  return 'Nomor terlalu pendek';
                }
                return null;
              },
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
                    ? const Icon(Icons.check_circle,
                        color: Colors.green, size: 20)
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
                    ? const Icon(Icons.check_circle,
                        color: Colors.green, size: 20)
                    : null,
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Kota tidak boleh kosong' : null,
            ),
            const SizedBox(height: 16),

            // Provinsi — terisi otomatis dari peta, bisa diedit
            TextFormField(
              controller: _provinceController,
              decoration: InputDecoration(
                labelText: 'Provinsi',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.map_outlined),
                suffixIcon: _locationPicked
                    ? const Icon(Icons.check_circle,
                        color: Colors.green, size: 20)
                    : null,
              ),
              validator: (v) => (v == null || v.isEmpty)
                  ? 'Provinsi tidak boleh kosong'
                  : null,
            ),
            const SizedBox(height: 16),

            // Kode Pos — terisi otomatis dari peta, bisa diedit
            TextFormField(
              controller: _postalCodeController,
              decoration: InputDecoration(
                labelText: 'Kode Pos',
                hintText: 'Contoh: 90234',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.markunread_mailbox_outlined),
                suffixIcon: _locationPicked
                    ? const Icon(Icons.check_circle,
                        color: Colors.green, size: 20)
                    : null,
              ),
              keyboardType: TextInputType.number,
              validator: (v) => (v == null || v.isEmpty)
                  ? 'Kode pos tidak boleh kosong'
                  : null,
            ),
            const SizedBox(height: 24),

            // ── STEP 3: Pilih Area Biteship ───────────────────────
            _buildSectionLabel('Langkah 3: Area Pengiriman (untuk cek ongkir)'),
            const SizedBox(height: 4),
            Text(
              'Pilih area agar ongkir otomatis tampil saat checkout '
              'tanpa perlu pencarian ulang.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 12),

            // BiteshipAreaSearchField dari widget yang sudah ada
            BiteshipAreaSearchField(
              label: 'Kecamatan / Kota Tujuan',
              initialArea: _selectedBiteshipArea,
              onAreaSelected: (area) {
                setState(() {
                  _selectedBiteshipArea = area;
                  // Auto-isi kode pos jika masih kosong
                  if (_postalCodeController.text.isEmpty &&
                      area.postalCode.isNotEmpty) {
                    _postalCodeController.text = area.postalCode;
                  }
                });
              },
            ),

            // Status indikator area terpilih
            if (_selectedBiteshipArea != null) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle,
                        color: Colors.green.shade700, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedBiteshipArea!.name,
                        style: TextStyle(
                          color: Colors.green.shade800,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: Colors.orange.shade700, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Belum dipilih — ongkir mungkin tidak muncul '
                        'otomatis di checkout.',
                        style: TextStyle(
                          color: Colors.orange.shade800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),

            // ── Set Default ───────────────────────────────────────
            SwitchListTile(
              value: _isDefault,
              onChanged: (v) => setState(() => _isDefault = v),
              title: const Text('Jadikan Alamat Utama'),
              subtitle:
                  const Text('Alamat ini akan dipilih otomatis saat checkout'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 32),

            // ── Tombol Simpan ─────────────────────────────────────
            GogamaButton(
              label: _isEditing ? 'Simpan Perubahan' : 'Simpan Alamat',
              isLoading: _isLoading,
              onPressed: _submit,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}