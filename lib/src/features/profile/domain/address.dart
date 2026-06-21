import 'package:cloud_firestore/cloud_firestore.dart';

class Address {
  final String id;
  final String label;
  final String name;
  final String phone;
  final String address;
  final String city;
  final String postalCode;
  final String province;
  final bool isDefault;

  // ── Koordinat GPS dari Google Maps ────────────────────────────
  final double? latitude;
  final double? longitude;

  // ── Biteship destination area (disimpan saat user input alamat) ──
  // Tujuan: skip searchArea() di checkout → langsung fetchRates()
  // Menghindari network call tambahan yang bisa gagal di Android
  final String? biteshipDestinationAreaId;
  final String? biteshipDestinationAreaName;

  /// True jika koordinat GPS sudah diisi — untuk GoSend/Grab
  bool get hasCoordinates => latitude != null && longitude != null;

  /// True jika area Biteship sudah tersimpan — skip searchArea() di checkout
  bool get hasBiteshipArea =>
      biteshipDestinationAreaId != null &&
      biteshipDestinationAreaId!.isNotEmpty;

  Address({
    required this.id,
    this.label = '',
    required this.name,
    required this.phone,
    required this.address,
    required this.city,
    required this.postalCode,
    required this.province,
    required this.isDefault,
    this.latitude,
    this.longitude,
    this.biteshipDestinationAreaId,
    this.biteshipDestinationAreaName,
  });

  factory Address.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Address(
      id: doc.id,
      label: data['label'] ?? '',
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      address: data['address'] ?? '',
      city: data['city'] ?? '',
      postalCode: data['postalCode'] ?? data['postal_code'] ?? '',
      province: data['province'] ?? '',
      isDefault: data['isDefault'] ?? false,
      // Koordinat GPS — null jika belum pernah disimpan
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      // Biteship area — null untuk alamat lama (akan fallback ke searchArea)
      biteshipDestinationAreaId: data['biteshipDestinationAreaId'] as String?,
      biteshipDestinationAreaName:
          data['biteshipDestinationAreaName'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'label': label,
      'name': name,
      'phone': phone,
      'address': address,
      'city': city,
      'postalCode': postalCode,
      'province': province,
      'isDefault': isDefault,
      // Simpan null jika tidak ada koordinat (tidak hapus field lama)
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      // Simpan area Biteship jika sudah dipilih user
      if (biteshipDestinationAreaId != null)
        'biteshipDestinationAreaId': biteshipDestinationAreaId,
      if (biteshipDestinationAreaName != null)
        'biteshipDestinationAreaName': biteshipDestinationAreaName,
      'updated_at': FieldValue.serverTimestamp(),
    };
  }

  Address copyWith({
    String? id,
    String? label,
    String? name,
    String? phone,
    String? address,
    String? city,
    String? postalCode,
    String? province,
    bool? isDefault,
    double? latitude,
    double? longitude,
    String? biteshipDestinationAreaId,
    String? biteshipDestinationAreaName,
  }) {
    return Address(
      id: id ?? this.id,
      label: label ?? this.label,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      city: city ?? this.city,
      postalCode: postalCode ?? this.postalCode,
      province: province ?? this.province,
      isDefault: isDefault ?? this.isDefault,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      biteshipDestinationAreaId:
          biteshipDestinationAreaId ?? this.biteshipDestinationAreaId,
      biteshipDestinationAreaName:
          biteshipDestinationAreaName ?? this.biteshipDestinationAreaName,
    );
  }
}
