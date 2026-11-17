
import 'invoice.dart';

class VisitRecord {
  final String date;
  final String doctor;
  final String notes;
  final String invoiceId;
  final double amount;
  final double consultationCharge;
  final double xrayCharge;
  final double pharmacyCharge;
  final double treatmentCharge;
  final List<CustomChargeItem> customCharges;

  VisitRecord({
    required this.date,
    required this.doctor,
    required this.notes,
    required this.invoiceId,
    required this.amount,
    this.consultationCharge = 0.0,
    this.xrayCharge = 0.0,
    this.pharmacyCharge = 0.0,
    this.treatmentCharge = 0.0,
    List<CustomChargeItem>? customCharges,
  }) : customCharges = customCharges ?? [];

  VisitRecord copyWith({
    String? date,
    String? doctor,
    String? notes,
    String? invoiceId,
    double? amount,
    double? consultationCharge,
    double? xrayCharge,
    double? pharmacyCharge,
    double? treatmentCharge,
    List<CustomChargeItem>? customCharges,
  }) => VisitRecord(
    date: date ?? this.date,
    doctor: doctor ?? this.doctor,
    notes: notes ?? this.notes,
    invoiceId: invoiceId ?? this.invoiceId,
    amount: amount ?? this.amount,
    consultationCharge: consultationCharge ?? this.consultationCharge,
    xrayCharge: xrayCharge ?? this.xrayCharge,
    pharmacyCharge: pharmacyCharge ?? this.pharmacyCharge,
    treatmentCharge: treatmentCharge ?? this.treatmentCharge,
    customCharges: customCharges ?? this.customCharges,
  );

  Map<String, dynamic> toJson() => {
    'date': date,
    'doctor': doctor,
    'notes': notes,
    'invoiceId': invoiceId,
    'amount': amount,
    'consultationCharge': consultationCharge,
    'xrayCharge': xrayCharge,
    'pharmacyCharge': pharmacyCharge,
    'treatmentCharge': treatmentCharge,
    'customCharges': customCharges.map((c) => c.toJson()).toList(),
  };

  factory VisitRecord.fromJson(Map<String, dynamic> json) {
    List<CustomChargeItem> customs = [];
    final rawCustom = json['customCharges'];
    if (rawCustom is List) {
      for (final it in rawCustom) {
        if (it is Map) {
          customs.add(CustomChargeItem.fromJson(Map<String, dynamic>.from(it)));
        }
      }
    }
    return VisitRecord(
      date: json['date'] ?? '',
      doctor: json['doctor'] ?? '',
      notes: json['notes'] ?? '',
      invoiceId: json['invoiceId'] ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      consultationCharge: (json['consultationCharge'] as num?)?.toDouble() ?? double.tryParse(json['consultationCharge']?.toString() ?? '') ?? 0.0,
      xrayCharge: (json['xrayCharge'] as num?)?.toDouble() ?? double.tryParse(json['xrayCharge']?.toString() ?? '') ?? 0.0,
      pharmacyCharge: (json['pharmacyCharge'] as num?)?.toDouble() ?? double.tryParse(json['pharmacyCharge']?.toString() ?? '') ?? 0.0,
      treatmentCharge: (json['treatmentCharge'] as num?)?.toDouble() ?? double.tryParse(json['treatmentCharge']?.toString() ?? '') ?? 0.0,
      customCharges: customs,
    );
  }
}

class Patient {
  final String id;
  final String opNumber;
  final String name;
  final String phone;
  final String email;
  final String dob;
  final int age;
  final String gender;
  final String address;
  final String doctor;
  final String medicalHistory;
  final String drugAllergies;
  final String diseaseHistory;
  final String registrationDate;
  int totalVisits;
  double totalBilled;
  List<VisitRecord> visits;

  Patient({
    required this.id,
    required this.opNumber,
    required this.name,
    required this.phone,
    this.email = '',
    this.dob = '',
    this.age = 0,
    required this.gender,
    this.address = '',
    required this.doctor,
    this.medicalHistory = '',
    this.drugAllergies = '',
    this.diseaseHistory = '',
    required this.registrationDate,
    this.totalVisits = 1,
    this.totalBilled = 0.0,
    List<VisitRecord>? visits,
  }) : visits = visits ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'opNumber': opNumber,
    'name': name,
    'phone': phone,
    'email': email,
    'dob': dob,
    'age': age,
    'gender': gender,
    'address': address,
    'doctor': doctor,
    'medicalHistory': medicalHistory,
    'drugAllergies': drugAllergies,
    'diseaseHistory': diseaseHistory,
    'registrationDate': registrationDate,
    'totalVisits': totalVisits,
    'totalBilled': totalBilled,
    'visits': visits.map((v) => v.toJson()).toList(),
  };

  factory Patient.fromJson(Map<String, dynamic> json) => Patient(
    id: json['id'] ?? '',
    opNumber: json['opNumber'] ?? '',
    name: json['name'] ?? '',
    phone: json['phone'] ?? '',
    email: json['email'] ?? '',
    dob: json['dob'] ?? '',
    age: (json['age'] as num?)?.toInt() ?? 0,
    gender: json['gender'] ?? 'Not Specified',
    address: json['address'] ?? '',
    doctor: json['doctor'] ?? 'Dr. Jeswin Jose BDS',
    medicalHistory: json['medicalHistory'] ?? '',
    drugAllergies: json['drugAllergies'] ?? '',
    diseaseHistory: json['diseaseHistory'] ?? '',
    registrationDate: json['registrationDate'] ?? '',
    totalVisits: (json['totalVisits'] as num?)?.toInt() ?? 1,
    totalBilled: (json['totalBilled'] as num?)?.toDouble() ?? 0.0,
    visits: (json['visits'] as List<dynamic>?)
            ?.map((e) => VisitRecord.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
  );
}
