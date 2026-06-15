import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// Hasil dari screen pemilihan lokasi
class LocationPickerResult {
  final double latitude;
  final double longitude;
  final String address;
  final String city;
  final String province;
  final String postalCode;

  const LocationPickerResult({
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.city,
    required this.province,
    required this.postalCode,
  });
}

class LocationPickerScreen extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;

  // ── WAJIB: API Key Google Maps Anda ──────────────────────────
  // Gunakan key yang sama dengan yang ada di web/index.html
  // dan AndroidManifest.xml / AppDelegate.swift
  static const String _googleApiKey = 'AIzaSyCMHbCIOjAIFbOs8VcT_wwWiLdz4BL65_A';

  const LocationPickerScreen({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  GoogleMapController? _mapController;

  static const _defaultPosition = LatLng(-5.1477, 119.4327); // Makassar

  late LatLng _selectedPosition;
  bool _isLoadingLocation = false;
  bool _isReverseGeocoding = false;
  String _addressPreview = 'Geser peta untuk memilih lokasi Anda';

  // ── Selalu isi dengan koordinat, address opsional ────────────
  // Ini memastikan tombol SELALU bisa diklik meski geocoding gagal
  LocationPickerResult? _currentResult;

  @override
  void initState() {
    super.initState();
    _selectedPosition =
        (widget.initialLatitude != null && widget.initialLongitude != null)
            ? LatLng(widget.initialLatitude!, widget.initialLongitude!)
            : _defaultPosition;

    // Set result awal dengan koordinat saja (tanpa alamat)
    // Ini memastikan tombol bisa diklik dari awal
    _currentResult = LocationPickerResult(
      latitude: _selectedPosition.latitude,
      longitude: _selectedPosition.longitude,
      address: '',
      city: '',
      province: '',
      postalCode: '',
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reverseGeocode(_selectedPosition);
    });
  }

  // ── GPS: dapatkan lokasi user ─────────────────────────────────
  Future<void> _goToMyLocation() async {
    setState(() => _isLoadingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMessage('Aktifkan GPS di pengaturan perangkat Anda.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showMessage('Izin lokasi ditolak.');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showMessage('Izin lokasi ditolak permanen. Buka Pengaturan Aplikasi.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final latLng = LatLng(position.latitude, position.longitude);
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
            CameraPosition(target: latLng, zoom: 17)),
      );
      setState(() => _selectedPosition = latLng);
      await _reverseGeocode(latLng);
    } catch (e) {
      _showMessage('Gagal mendapatkan lokasi: $e');
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  // ── Reverse geocoding via Google Maps Geocoding API (HTTP) ───
  // Mendukung Android, iOS, DAN Web
  Future<void> _reverseGeocode(LatLng position) async {
    setState(() {
      _isReverseGeocoding = true;
      _addressPreview = 'Mencari alamat...';

      // Update koordinat di _currentResult segera
      // Tombol tetap bisa diklik meski nama jalan belum tersedia
      _currentResult = LocationPickerResult(
        latitude: position.latitude,
        longitude: position.longitude,
        address: _currentResult?.address ?? '',
        city: _currentResult?.city ?? '',
        province: _currentResult?.province ?? '',
        postalCode: _currentResult?.postalCode ?? '',
      );
    });

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${position.latitude},${position.longitude}'
        '&key=${LocationPickerScreen._googleApiKey}'
        '&language=id'
        '&result_type=street_address|sublocality|locality',
      );

      final response = await http.get(url);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String;

      if (status != 'OK') {
        // Geocoding gagal tapi koordinat sudah tersimpan — tetap lanjut
        if (mounted) {
          setState(() {
            _addressPreview =
                'Alamat tidak ditemukan — koordinat tetap tersimpan';
            _isReverseGeocoding = false;
          });
        }
        return;
      }

      final results = data['results'] as List<dynamic>;
      if (results.isEmpty) {
        if (mounted) {
          setState(() {
            _addressPreview = 'Tidak ada hasil — koordinat tetap tersimpan';
            _isReverseGeocoding = false;
          });
        }
        return;
      }

      // Ambil komponen alamat dari hasil pertama
      final firstResult = results.first as Map<String, dynamic>;
      final components = firstResult['address_components'] as List<dynamic>;

      String streetNumber = '';
      String route = '';
      String sublocality = '';
      String locality = '';
      String city = '';
      String province = '';
      String postalCode = '';

      for (final component in components) {
        final types = (component['types'] as List<dynamic>).cast<String>();
        final longName = component['long_name'] as String;

        if (types.contains('street_number')) streetNumber = longName;
        if (types.contains('route')) route = longName;
        if (types.contains('sublocality_level_1') ||
            types.contains('sublocality')) {
          sublocality = longName;
        }
        if (types.contains('locality')) locality = longName;
        if (types.contains('administrative_area_level_2')) city = longName;
        if (types.contains('administrative_area_level_1')) province = longName;
        if (types.contains('postal_code')) postalCode = longName;
      }

      // Susun alamat lengkap
      final streetParts = [
        if (route.isNotEmpty)
          '$route${streetNumber.isNotEmpty ? ' No.$streetNumber' : ''}',
        if (sublocality.isNotEmpty) sublocality,
        if (locality.isNotEmpty) locality,
      ];
      final fullAddress = streetParts.join(', ');
      final resolvedCity = city.isNotEmpty ? city : locality;

      // Preview di UI
      final previewParts = [
        if (fullAddress.isNotEmpty) fullAddress,
        if (resolvedCity.isNotEmpty) resolvedCity,
        if (province.isNotEmpty) province,
      ];

      if (mounted) {
        setState(() {
          _addressPreview = previewParts.isNotEmpty
              ? previewParts.join(', ')
              : firstResult['formatted_address'] as String? ?? '-';

          // Update _currentResult dengan alamat lengkap
          _currentResult = LocationPickerResult(
            latitude: position.latitude,
            longitude: position.longitude,
            address: fullAddress.isNotEmpty
                ? fullAddress
                : (firstResult['formatted_address'] as String? ?? ''),
            city: resolvedCity,
            province: province,
            postalCode: postalCode,
          );

          _isReverseGeocoding = false;
        });
      }
    } catch (e) {
      // Error network — koordinat sudah tersimpan, lanjutkan
      if (mounted) {
        setState(() {
          _addressPreview =
              'Gagal mendapatkan nama jalan — koordinat tetap tersimpan';
          _isReverseGeocoding = false;
          // _currentResult sudah berisi koordinat, jangan null-kan
        });
      }
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _confirmSelection() {
    // _currentResult selalu ada (diisi di initState & setiap camera move)
    Navigator.of(context).pop(_currentResult);
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pilih Lokasi'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _confirmSelection, // Selalu bisa diklik
            child: const Text(
              'Pilih',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Peta ─────────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _selectedPosition,
              zoom: 16,
            ),
            onMapCreated: (controller) => _mapController = controller,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onCameraMove: (position) {
              _selectedPosition = position.target;
              // Update koordinat real-time saat peta digeser
              _currentResult = LocationPickerResult(
                latitude: position.target.latitude,
                longitude: position.target.longitude,
                address: _currentResult?.address ?? '',
                city: _currentResult?.city ?? '',
                province: _currentResult?.province ?? '',
                postalCode: _currentResult?.postalCode ?? '',
              );
            },
            onCameraIdle: () => _reverseGeocode(_selectedPosition),
          ),

          // ── Pin tengah (statis) ───────────────────────────────
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_pin, color: Colors.red, size: 48),
                SizedBox(height: 48),
              ],
            ),
          ),

          // ── Tombol GPS ────────────────────────────────────────
          Positioned(
            right: 16,
            bottom: 200,
            child: FloatingActionButton.small(
              heroTag: 'my_location',
              onPressed: _isLoadingLocation ? null : _goToMyLocation,
              backgroundColor: Colors.white,
              child: _isLoadingLocation
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location, color: Colors.blue),
            ),
          ),

          // ── Panel bawah: preview + tombol konfirmasi ──────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  const Text(
                    'Lokasi yang dipilih:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),

                  // Preview alamat
                  Row(
                    children: [
                      Icon(Icons.location_on, color: Colors.red[400], size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _isReverseGeocoding
                            ? Row(
                                children: [
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Mencari nama jalan...',
                                    style: TextStyle(
                                        color: Colors.grey[600], fontSize: 13),
                                  ),
                                ],
                              )
                            : Text(
                                _addressPreview,
                                style: const TextStyle(fontSize: 14),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Koordinat
                  Text(
                    '${_selectedPosition.latitude.toStringAsFixed(6)}, '
                    '${_selectedPosition.longitude.toStringAsFixed(6)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),

                  const SizedBox(height: 16),

                  // Tombol konfirmasi — SELALU aktif setelah koordinat dipilih
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      // Tidak pernah null — koordinat selalu ada
                      onPressed: _confirmSelection,
                      icon: const Icon(Icons.check),
                      label: Text(
                        _isReverseGeocoding
                            ? 'Gunakan Koordinat Ini'
                            : 'Gunakan Lokasi Ini',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),

                  // Info jika geocoding sedang berjalan
                  if (_isReverseGeocoding) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Nama jalan sedang dimuat, Anda bisa langsung pilih',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Banner panduan ────────────────────────────────────
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.touch_app, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Geser peta untuk menempatkan pin tepat di lokasi Anda',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
