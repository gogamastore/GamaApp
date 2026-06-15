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

  // ── BARU: koordinat GPS dari Google Maps ──────────────────────
  final double? latitude;
  final double? longitude;

  /// True jika koordinat sudah diisi — dipakai untuk GoSend/Grab
  bool get hasCoordinates => latitude != null && longitude != null;

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
      // Baca koordinat — null jika belum pernah disimpan
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
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
      'created_at': FieldValue.serverTimestamp(),
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
    );
  }
}
