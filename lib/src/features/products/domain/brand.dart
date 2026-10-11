class Brand {
  final String id;
  final String name;
  final String logoUrl;

  Brand({
    this.id = '',
    required this.name,
    required this.logoUrl,
  });

  factory Brand.fromMap(Map<String, dynamic> map, {String id = ''}) {
    return Brand(
      id: id,
      name: map['name'] as String? ?? '',
      logoUrl: map['logoUrl'] as String? ?? '',
    );
  }
}
