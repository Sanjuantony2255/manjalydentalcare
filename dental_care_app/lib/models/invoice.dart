import 'dart:convert';

class CustomChargeItem {
  final String title;
  final double amount;

  CustomChargeItem({
    required this.title,
    required this.amount,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'amount': amount,
  };

  factory CustomChargeItem.fromJson(Map<String, dynamic> json) => CustomChargeItem(
    title: (json['title'] ?? json['name'] ?? json['description'] ?? '').toString(),
    amount: (json['amount'] is num)
        ? (json['amount'] as num).toDouble()
        : double.tryParse((json['amount'] ?? '').toString().replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0,
  );
}

class Invoice {
  final String id;
  final String patientName;
  final String phone;
  final String doctor;
  final String date; // YYYY-MM-DD
  final String address;
  final String opNumber;
  final double consultationCharge;
  final double xrayCharge;
  final double pharmacyCharge;
  final double treatmentCharge;
  final String treatment;
  final int treatmentNos;
  final double treatmentRate;
  final List<CustomChargeItem> customCharges;
  final double totalAmount;
  final String paymentMode; // 'Cash', 'UPI / Online', 'Card', 'Pending'
  final String notes;

  String get doctorConsulted => doctor;

  Invoice({
    required this.id,
    required this.patientName,
    required this.phone,
    required this.doctor,
    required this.date,
    this.address = '',
    this.opNumber = '',
    this.consultationCharge = 0.0,
    this.xrayCharge = 0.0,
    this.pharmacyCharge = 0.0,
    this.treatmentCharge = 0.0,
    this.treatment = '',
    this.treatmentNos = 1,
    this.treatmentRate = 0.0,
    List<CustomChargeItem>? customCharges,
    required this.totalAmount,
    required this.paymentMode,
    this.notes = '',
  }) : customCharges = customCharges ?? [];

  Invoice copyWith({
    String? id,
    String? patientName,
    String? phone,
    String? doctor,
    String? date,
    String? address,
    String? opNumber,
    double? consultationCharge,
    double? xrayCharge,
    double? pharmacyCharge,
    double? treatmentCharge,
    String? treatment,
    int? treatmentNos,
    double? treatmentRate,
    List<CustomChargeItem>? customCharges,
    double? totalAmount,
    String? paymentMode,
    String? notes,
  }) {
    return Invoice(
      id: id ?? this.id,
      patientName: patientName ?? this.patientName,
      phone: phone ?? this.phone,
      doctor: doctor ?? this.doctor,
      date: date ?? this.date,
      address: address ?? this.address,
      opNumber: opNumber ?? this.opNumber,
      consultationCharge: consultationCharge ?? this.consultationCharge,
      xrayCharge: xrayCharge ?? this.xrayCharge,
      pharmacyCharge: pharmacyCharge ?? this.pharmacyCharge,
      treatmentCharge: treatmentCharge ?? this.treatmentCharge,
      treatment: treatment ?? this.treatment,
      treatmentNos: treatmentNos ?? this.treatmentNos,
      treatmentRate: treatmentRate ?? this.treatmentRate,
      customCharges: customCharges ?? List.from(this.customCharges),
      totalAmount: totalAmount ?? this.totalAmount,
      paymentMode: paymentMode ?? this.paymentMode,
      notes: notes ?? this.notes,
    );
  }

  Invoice mergeWith(Invoice other) {
    return Invoice(
      id: id.isNotEmpty ? id : other.id,
      patientName: patientName.isNotEmpty ? patientName : other.patientName,
      phone: phone.isNotEmpty ? phone : other.phone,
      doctor: (doctor.isNotEmpty && doctor != 'Dr. Jeswin Jose BDS') ? doctor : other.doctor,
      date: date.isNotEmpty ? date : other.date,
      address: address.isNotEmpty ? address : other.address,
      opNumber: opNumber.isNotEmpty ? opNumber : other.opNumber,
      consultationCharge: consultationCharge > 0 ? consultationCharge : other.consultationCharge,
      xrayCharge: xrayCharge > 0 ? xrayCharge : other.xrayCharge,
      pharmacyCharge: pharmacyCharge > 0 ? pharmacyCharge : other.pharmacyCharge,
      treatmentCharge: treatmentCharge > 0 ? treatmentCharge : other.treatmentCharge,
      treatment: treatment.isNotEmpty ? treatment : other.treatment,
      treatmentNos: treatmentNos > 1 ? treatmentNos : other.treatmentNos,
      treatmentRate: treatmentRate > 0 ? treatmentRate : other.treatmentRate,
      customCharges: customCharges.isNotEmpty ? customCharges : other.customCharges,
      totalAmount: totalAmount > 0 ? totalAmount : other.totalAmount,
      paymentMode: (paymentMode.isNotEmpty && paymentMode != 'Cash') ? paymentMode : (other.paymentMode.isNotEmpty ? other.paymentMode : 'Cash'),
      notes: notes.isNotEmpty ? notes : other.notes,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'patientName': patientName,
    'phone': phone,
    'doctor': doctor,
    'date': date,
    'address': address,
    'opNumber': opNumber,
    'consultationCharge': consultationCharge,
    'xrayCharge': xrayCharge,
    'pharmacyCharge': pharmacyCharge,
    'treatmentCharge': treatmentCharge,
    'treatment': treatment,
    'treatmentNos': treatmentNos,
    'treatmentRate': treatmentRate > 0 ? treatmentRate : treatmentCharge,
    'customCharges': customCharges.map((c) => c.toJson()).toList(),
    'totalAmount': totalAmount,
    'paymentMode': paymentMode,
    'notes': notes,
  };

  factory Invoice.fromJson(Map<String, dynamic> json) {
    double parseNum(dynamic val) {
      if (val == null) return 0.0;
      if (val is num) return val.toDouble();
      final s = val.toString().replaceAll(RegExp(r'[^0-9.]'), '');
      return double.tryParse(s) ?? 0.0;
    }

    final tCharge = parseNum(json['treatmentCharge']);
    final rawNos = json['treatmentNos'];
    final tNos = rawNos is num ? rawNos.toInt() : (int.tryParse(rawNos?.toString() ?? '') ?? 1);
    final rawRate = parseNum(json['treatmentRate']);
    final tRate = rawRate > 0 ? rawRate : (tNos > 0 && tCharge > 0 ? (tCharge / tNos) : tCharge);

    List<CustomChargeItem> parsedCustom = [];
    final rawCustom = json['customCharges'];
    if (rawCustom is List) {
      for (final item in rawCustom) {
        if (item is Map<String, dynamic>) {
          parsedCustom.add(CustomChargeItem.fromJson(item));
        } else if (item is Map) {
          parsedCustom.add(CustomChargeItem.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    } else if (rawCustom is String && rawCustom.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawCustom.trim());
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              parsedCustom.add(CustomChargeItem.fromJson(Map<String, dynamic>.from(item)));
            }
          }
        }
      } catch (_) {}
    }

    final id = (json['id'] ?? json['invoiceNo'] ?? json['invoiceNumber'] ?? json['billNo'] ?? '').toString();
    final patientName = (json['patientName'] ?? json['fullName'] ?? json['name'] ?? '').toString();
    final phone = (json['phone'] ?? json['mobile'] ?? '').toString();
    final doctor = (json['doctor'] ?? json['doctorConsulted'] ?? 'Dr. Jeswin Jose BDS').toString();
    final date = (json['date'] ?? json['timestamp'] ?? '').toString();
    final address = (json['address'] ?? json['email'] ?? '').toString();
    final opNumber = (json['opNumber'] ?? json['op_number'] ?? json['opNo'] ?? json['op'] ?? '').toString().trim();
    final consultationCharge = parseNum(json['consultationCharge'] ?? json['consultation']);
    final xrayCharge = parseNum(json['xrayCharge'] ?? json['xray']);
    final pharmacyCharge = parseNum(json['pharmacyCharge'] ?? json['pharmacy']);
    final treatment = (json['treatment'] ?? json['procedure'] ?? json['diseaseHistory'] ?? json['notes'] ?? '').toString();
    final totalAmount = parseNum(json['totalAmount'] ?? json['total']);
    final paymentMode = (json['paymentMode'] ?? json['payment'] ?? 'Cash').toString();
    final notes = (json['notes'] ?? '').toString();

    return Invoice(
      id: id,
      patientName: patientName,
      phone: phone,
      doctor: doctor.isNotEmpty ? doctor : 'Dr. Jeswin Jose BDS',
      date: date,
      address: address,
      opNumber: opNumber,
      consultationCharge: consultationCharge,
      xrayCharge: xrayCharge,
      pharmacyCharge: pharmacyCharge,
      treatmentCharge: tCharge,
      treatment: treatment,
      treatmentNos: tNos > 0 ? tNos : 1,
      treatmentRate: tRate,
      customCharges: parsedCustom,
      totalAmount: totalAmount > 0 ? totalAmount : (consultationCharge + xrayCharge + pharmacyCharge + tCharge),
      paymentMode: paymentMode.isNotEmpty ? paymentMode : 'Cash',
      notes: notes,
    );
  }
}
