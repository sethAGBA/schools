class Supplier {
  final int? id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final String createdAt;
  final String updatedAt;

  Supplier({
    this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'email': email,
      'address': address,
      'notes': notes,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory Supplier.fromMap(Map<String, dynamic> map) {
    return Supplier(
      id: (map['id'] as num?)?.toInt(),
      name: map['name']?.toString() ?? '',
      phone: map['phone']?.toString(),
      email: map['email']?.toString(),
      address: map['address']?.toString(),
      notes: map['notes']?.toString(),
      createdAt: map['createdAt']?.toString() ?? '',
      updatedAt: map['updatedAt']?.toString() ?? '',
    );
  }
}

