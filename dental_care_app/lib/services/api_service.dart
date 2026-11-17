import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/patient.dart';
import '../models/appointment.dart';
import '../models/invoice.dart';
import '../models/inventory_item.dart';

class ApiService {
  static const String githubCloudDataUrl =
      'https://raw.githubusercontent.com/Sanjuantony2255/manjalydentalcare/main/clinic_data.json';
  static const String spreadsheetId = '1MuzymftW2wzDV5C-ljLKXHo_NyqK6Xxp-PlI7pqbhls';
  static const String defaultScriptUrl =
      'https://script.google.com/macros/s/AKfycbyC1zFwfNFa8w-wLJGdEE9ladkNL2rZk-gIfx68CX76upxyQrI1Lar8Tb6BGEvLX4q0/exec';

  static const String patientsSheetCsvUrl =
      'https://docs.google.com/spreadsheets/d/$spreadsheetId/gviz/tq?tqx=out:csv';
  static const String appointmentsSheetCsvUrl =
      'https://docs.google.com/spreadsheets/d/$spreadsheetId/gviz/tq?tqx=out:csv&sheet=Appointments';
  static const String invoicesSheetCsvUrl =
      'https://docs.google.com/spreadsheets/d/$spreadsheetId/gviz/tq?tqx=out:csv&sheet=Invoices';

  /// Posts appointment to Google Apps Script / Google Calendar
  static Future<bool> syncAppointmentOnline(Appointment apt) async {
    try {
      final response = await http.post(
        Uri.parse(defaultScriptUrl),
        body: {
          'action': 'addAppointment',
          'patientName': apt.patientName,
          'phone': apt.phone,
          'doctor': apt.doctor,
          'date': apt.date,
          'time': apt.timeSlot,
          'timeSlot': apt.timeSlot,
          'reason': apt.reason,
          'notes': apt.notes,
        },
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200 || response.statusCode == 302;
    } catch (_) {
      return false;
    }
  }

  /// Reschedules an appointment in the Google Cloud database
  static Future<bool> rescheduleAppointmentOnline(
    String appointmentId,
    String phone,
    String newDate,
    String newTime,
    String doctor,
    String notes,
  ) async {
    try {
      final response = await http.post(
        Uri.parse(defaultScriptUrl),
        body: {
          'action': 'rescheduleAppointment',
          'appointmentId': appointmentId,
          'phone': phone,
          'newDate': newDate,
          'newTime': newTime,
          'doctor': doctor,
          'notes': notes,
        },
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200 || response.statusCode == 302;
    } catch (_) {
      return false;
    }
  }

  /// Updates status in Google Apps Script (e.g. Completed / Cancelled / Upcoming)
  static Future<bool> updateAppointmentStatusOnline(
    String appointmentId,
    String newStatus,
  ) async {
    try {
      final response = await http.post(
        Uri.parse(defaultScriptUrl),
        body: {
          'action': 'updateAppointmentStatus',
          'appointmentId': appointmentId,
          'status': newStatus,
        },
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200 || response.statusCode == 302;
    } catch (_) {
      return false;
    }
  }

  /// Posts patient registration and invoice to Google Apps Script & Google Sheet
  static Future<bool> syncRegistrationOnline(Patient patient, Invoice invoice) async {
    try {
      final response = await http.post(
        Uri.parse(defaultScriptUrl),
        body: {
          'action': 'registerPatient',
          'fullName': patient.name,
          'name': patient.name,
          'phone': patient.phone,
          'age': patient.age.toString(),
          'dob': patient.dob,
          'gender': patient.gender,
          'address': patient.address,
          'opNumber': patient.opNumber,
          'doctor': patient.doctor,
          'doctorConsulted': patient.doctor,
          'medicalHistory': patient.medicalHistory,
          'drugAllergies': patient.drugAllergies,
          'diseaseHistory': patient.diseaseHistory,
          'treatment': invoice.treatment.isNotEmpty ? invoice.treatment : patient.diseaseHistory,
          'treatmentCharge': invoice.treatmentCharge.toString(),
          'treatmentNos': invoice.treatmentNos.toString(),
          'treatmentRate': invoice.treatmentRate.toString(),
          'customCharges': jsonEncode(invoice.customCharges.map((c) => c.toJson()).toList()),
          'consultationCharge': invoice.consultationCharge.toString(),
          'xrayCharge': invoice.xrayCharge.toString(),
          'pharmacyCharge': invoice.pharmacyCharge.toString(),
          'totalAmount': invoice.totalAmount.toString(),
          'paymentMode': invoice.paymentMode,
          'notes': invoice.notes,
          'date': invoice.date,
          'timestamp': invoice.date,
          'lastVisitDate': invoice.date,
          'invoiceNumber': invoice.id,
          'invoiceNo': invoice.id,
        },
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200 || response.statusCode == 302;
    } catch (_) {
      return false;
    }
  }

  /// Parses CSV table data handling standard quoted cells and commas
  static List<List<String>> _parseCsv(String csv) {
    final List<List<String>> rows = [];
    final lines = const LineSplitter().convert(csv);

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final List<String> row = [];
      final matches = RegExp(r'(?:^|,)(?:"([^"]*(?:""[^"]*)*)"|([^",]*))').allMatches(line);
      for (final match in matches) {
        String cell = match.group(1) ?? match.group(2) ?? '';
        cell = cell.replaceAll('""', '"').trim();
        row.add(cell);
      }
      if (row.isNotEmpty) {
        rows.add(row);
      }
    }
    return rows;
  }

  /// Dynamically locates the column index from header row based on keywords
  static int _findCol(List<String> headers, List<String> patterns, int fallback, {List<String> excludes = const []}) {
    for (int i = 0; i < headers.length; i++) {
      final h = headers[i].toLowerCase().trim();
      if (excludes.any((ex) => h.contains(ex.toLowerCase()))) continue;
      for (final p in patterns) {
        if (h.contains(p.toLowerCase())) return i;
      }
    }
    return fallback;
  }

  /// Safely retrieves a cell value from a row avoiding RangeError exceptions
  static String _safeCell(List<String> row, int index) {
    if (index >= 0 && index < row.length) {
      return row[index].trim();
    }
    return '';
  }

  /// Fetches live data from GitHub Cloud repository AND Google Sheet cloud
  static Future<Map<String, dynamic>> fetchCloudData() async {
    final List<Patient> patients = [];
    final List<Appointment> appointments = [];
    final List<Invoice> invoices = [];
    final List<InventoryItem> inventory = [];

    // Helper checks to filter out any test dummy data
    bool isDummyPatient(String name, String phone, String id) {
      final n = name.trim().toLowerCase();
      final p = phone.trim();
      return n == 'test patient' || n == 'rajesh kumar' || n == 'ramesh kumar' ||
          p == '9845012345' || p == '9876543210' || p == '9998887776' ||
          p == '133564456156' || id == 'PAT-133564456156' || id == 'PAT-1001' || id == 'PAT-9876543210';
    }

    bool isDummyAppointment(String id, String name, String phone) {
      final n = name.trim().toLowerCase();
      final p = phone.trim();
      return n == 'test patient' || n == 'rajesh kumar' || n == 'ramesh kumar' ||
          p == '9845012345' || p == '9876543210' || p == '9998887776' ||
          id.contains('20261024-00') || id == 'APT-20261014-4821' || id == 'APT-20261013-2755';
    }

    bool isDummyInvoice(String id, String name) {
      final n = name.trim().toLowerCase();
      return n == 'test patient' || n == 'rajesh kumar' || n == 'ramesh kumar' ||
          id == 'INV-2026-001' || id == 'INV-20261013-3604' || id == 'INV-20261013-3503' ||
          id == 'INV-20261013-2386' || id == 'INV-20261014-9713';
    }

    // Direct Google Apps Script and Google Sheet fetching only (no static dummy data)
    // 1. Fetch Google Apps Script live Patients
    final List<Patient> livePatients = [];
    try {
      final res = await http.get(Uri.parse('$defaultScriptUrl?action=getPatients')).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final data = jsonDecode(res.body);
        if (data is Map && data['status'] == 'success' && data['data'] is List) {
          for (final item in data['data']) {
            final name = item['fullName']?.toString().trim() ?? '';
            final phone = item['phone']?.toString().trim() ?? '';
            if (name.isEmpty && phone.isEmpty) continue;
            if (isDummyPatient(name, phone, '')) continue;

            final email = item['email']?.toString() ?? '';
            final dob = item['dob']?.toString() ?? '';
            final gender = item['gender']?.toString() ?? 'Male';
            final doctor = item['doctorConsulted']?.toString() ?? 'Dr. Jeswin Jose BDS';
            final medHistory = item['medicalHistory']?.toString() ?? 'None';
            final diseaseHistory = item['diseaseHistory']?.toString() ?? '';
            final latestVisit = item['latestVisit']?.toString() ?? '2026-10-14';
            final visitsCount = (item['visitsCount'] as num?)?.toInt() ?? 1;
            final totalBilled = (item['totalBilled'] as num?)?.toDouble() ?? 0.0;

            final rawOp = item['opNumber']?.toString().trim() ?? '';
            final effectiveOp = rawOp.isNotEmpty ? rawOp : 'OP-${(name.hashCode.abs() % 900) + 100}';

            final List<VisitRecord> visits = [];
            if (item['visits'] is List) {
              for (final v in item['visits']) {
                if (v is Map) {
                  final vDate = v['date']?.toString() ?? v['timestamp']?.toString().split(' ').first ?? latestVisit;
                  final vDoc = v['doctor']?.toString() ?? v['doctorConsulted']?.toString() ?? doctor;
                  final vTreatDesc = v['treatment']?.toString() ?? v['notes']?.toString() ?? v['diseaseHistory']?.toString() ?? diseaseHistory;
                  final vNotes = v['notes']?.toString() ?? vTreatDesc;
                  final vInvNo = v['invoiceId']?.toString() ?? v['invoiceNo']?.toString() ?? 'INV-SHEET';
                  final vTot = (v['amount'] as num?)?.toDouble() ?? (v['totalAmount'] as num?)?.toDouble() ?? 0.0;
                  final vConsult = (v['consultationCharge'] as num?)?.toDouble() ?? double.tryParse(v['consultationCharge']?.toString() ?? '') ?? 0.0;
                  final vXray = (v['xrayCharge'] as num?)?.toDouble() ?? double.tryParse(v['xrayCharge']?.toString() ?? '') ?? 0.0;
                  final vPharm = (v['pharmacyCharge'] as num?)?.toDouble() ?? double.tryParse(v['pharmacyCharge']?.toString() ?? '') ?? 0.0;
                  final vPayMode = v['paymentMode']?.toString() ?? 'Cash';

                  List<CustomChargeItem> vCustoms = [];
                  final rawCustom = v['customCharges'];
                  if (rawCustom is List) {
                    for (final ci in rawCustom) {
                      if (ci is Map) vCustoms.add(CustomChargeItem.fromJson(Map<String, dynamic>.from(ci)));
                    }
                  } else if (rawCustom is String && rawCustom.isNotEmpty) {
                    try {
                      final dec = jsonDecode(rawCustom);
                      if (dec is List) {
                        for (final ci in dec) {
                          if (ci is Map) vCustoms.add(CustomChargeItem.fromJson(Map<String, dynamic>.from(ci)));
                        }
                      }
                    } catch (_) {}
                  }

                  final customSum = vCustoms.fold<double>(0.0, (s, c) => s + c.amount);
                  final otherSum = vConsult + vXray + vPharm + customSum;
                  double vTreatCharge = (v['treatmentCharge'] as num?)?.toDouble() ?? double.tryParse(v['treatmentCharge']?.toString() ?? '') ?? 0.0;
                  if (vTreatCharge <= 0 && vTot > otherSum) {
                    vTreatCharge = vTot - otherSum;
                  }
                  final vTreatNos = (v['treatmentNos'] as num?)?.toInt() ?? int.tryParse(v['treatmentNos']?.toString() ?? '') ?? 1;
                  final vTreatRate = (v['treatmentRate'] as num?)?.toDouble() ?? double.tryParse(v['treatmentRate']?.toString() ?? '') ?? (vTreatNos > 0 ? (vTreatCharge / vTreatNos) : vTreatCharge);

                  visits.add(VisitRecord(
                    date: vDate,
                    doctor: vDoc,
                    notes: vTreatDesc.isNotEmpty ? vTreatDesc : vNotes,
                    invoiceId: vInvNo,
                    amount: vTot,
                    consultationCharge: vConsult,
                    xrayCharge: vXray,
                    pharmacyCharge: vPharm,
                    treatmentCharge: vTreatCharge,
                    customCharges: vCustoms,
                  ));

                  if (vInvNo.isNotEmpty && !vInvNo.toLowerCase().contains('sheet') && !isDummyInvoice(vInvNo, name)) {
                    final visitInv = Invoice(
                      id: vInvNo,
                      patientName: name,
                      phone: phone,
                      doctor: vDoc,
                      date: vDate,
                      address: email,
                      opNumber: effectiveOp,
                      consultationCharge: vConsult,
                      xrayCharge: vXray,
                      pharmacyCharge: vPharm,
                      treatmentCharge: vTreatCharge,
                      treatment: vTreatDesc,
                      treatmentNos: vTreatNos > 0 ? vTreatNos : 1,
                      treatmentRate: vTreatRate,
                      customCharges: vCustoms,
                      totalAmount: vTot,
                      paymentMode: vPayMode,
                      notes: vNotes,
                    );
                    final exIdx = invoices.indexWhere((it) => it.id.toLowerCase() == visitInv.id.toLowerCase());
                    if (exIdx >= 0) {
                      invoices[exIdx] = invoices[exIdx].copyWith(
                        treatment: invoices[exIdx].treatment.isNotEmpty ? invoices[exIdx].treatment : visitInv.treatment,
                        treatmentCharge: invoices[exIdx].treatmentCharge > 0 ? invoices[exIdx].treatmentCharge : visitInv.treatmentCharge,
                        treatmentNos: invoices[exIdx].treatmentNos > 0 ? invoices[exIdx].treatmentNos : visitInv.treatmentNos,
                        treatmentRate: invoices[exIdx].treatmentRate > 0 ? invoices[exIdx].treatmentRate : visitInv.treatmentRate,
                        consultationCharge: invoices[exIdx].consultationCharge > 0 ? invoices[exIdx].consultationCharge : visitInv.consultationCharge,
                        xrayCharge: invoices[exIdx].xrayCharge > 0 ? invoices[exIdx].xrayCharge : visitInv.xrayCharge,
                        pharmacyCharge: invoices[exIdx].pharmacyCharge > 0 ? invoices[exIdx].pharmacyCharge : visitInv.pharmacyCharge,
                        customCharges: invoices[exIdx].customCharges.isNotEmpty ? invoices[exIdx].customCharges : visitInv.customCharges,
                        opNumber: invoices[exIdx].opNumber.isNotEmpty ? invoices[exIdx].opNumber : visitInv.opNumber,
                      );
                    } else {
                      invoices.add(visitInv);
                    }
                  }
                }
              }
            }

            final parsedPatient = Patient(
              id: phone.isNotEmpty ? 'PAT-$phone' : 'PAT-${name.hashCode.abs()}',
              opNumber: effectiveOp,
              name: name,
              phone: phone,
              email: email,
              dob: dob,
              gender: gender,
              doctor: doctor,
              medicalHistory: medHistory,
              diseaseHistory: diseaseHistory,
              registrationDate: latestVisit,
              totalVisits: visitsCount,
              totalBilled: totalBilled,
              visits: visits,
            );

            livePatients.add(parsedPatient);
          }
        }
      }
    } catch (_) {}

    if (livePatients.isNotEmpty) {
      patients.clear();
      patients.addAll(livePatients);
    } else {
      // Direct Google Sheet CSV Fallback for Patients
      try {
        final res = await http.get(Uri.parse(patientsSheetCsvUrl)).timeout(const Duration(seconds: 10));
        if (res.statusCode == 200 && res.body.isNotEmpty) {
          final rows = _parseCsv(res.body);
          if (rows.isNotEmpty) {
            final headers = rows[0];
            final hasHeader = headers.any((h) =>
                h.toLowerCase().contains('time') ||
                h.toLowerCase().contains('name') ||
                h.toLowerCase().contains('phone') ||
                h.toLowerCase().contains('op'));

            final colTime = _findCol(headers, ['timestamp', 'time', 'date'], 0);
            final colOp = _findCol(headers, ['op number', 'op no', 'opnum', 'op#', 'op', 'patient id'], -1);
            final colName = _findCol(headers, ['full name', 'patient name', 'name'], 1);
            final colPhone = _findCol(headers, ['phone', 'mobile', 'contact'], 2);
            final colEmail = _findCol(headers, ['email', 'mail'], 3);
            final colDob = _findCol(headers, ['dob', 'birth', 'age'], 4);
            final colGender = _findCol(headers, ['gender', 'sex'], 5);
            final colDoctor = _findCol(headers, ['doctor', 'attending', 'consulted'], 6, excludes: ['charge', 'fee', 'amount']);
            final colMedHist = _findCol(headers, ['medical'], 7);
            final colAllergies = _findCol(headers, ['allerg', 'drug'], 8);
            final colDisease = _findCol(headers, ['disease', 'complaint'], 9);
            final colTreatment = _findCol(headers, ['treatment name', 'treatment procedure', 'treatment'], -1, excludes: ['charge', 'rate', 'nos', 'cost', 'fee', 'amount']);
            final colTreatmentCharge = _findCol(headers, ['treatment charge', 'procedure charge', 'treatment fee'], -1);
            final colConsult = _findCol(headers, ['consultation charge', 'consult charge', 'consultation fee', 'consult fee', 'consultation', 'consult'], 10, excludes: ['doctor', 'dentist']);
            final colXray = _findCol(headers, ['xray', 'x-ray'], 11);
            final colPharm = _findCol(headers, ['pharm', 'medicin'], 12);
            final colCustom = _findCol(headers, ['custom charges', 'custom', 'extra'], -1);
            final colTotal = _findCol(headers, ['total', 'amount'], 13);
            final colInv = _findCol(headers, ['invoice'], 16);

            final List<Patient> csvPatients = [];
            final startIdx = hasHeader ? 1 : 0;
            for (int i = startIdx; i < rows.length; i++) {
              final r = rows[i];
              if (r.isEmpty) continue;
              final timestamp = _safeCell(r, colTime);
              if (timestamp.toLowerCase().contains('timestamp')) continue;
              final name = _safeCell(r, colName);
              final phone = _safeCell(r, colPhone);
              final rawOp = colOp >= 0 ? _safeCell(r, colOp) : '';
              if (name.isEmpty && phone.isEmpty && rawOp.isEmpty) continue;
              if (isDummyPatient(name, phone, '')) continue;

              final email = _safeCell(r, colEmail);
              final dob = _safeCell(r, colDob);
              final gender = _safeCell(r, colGender).isNotEmpty ? _safeCell(r, colGender) : 'Male';
              final rawDoc = _safeCell(r, colDoctor);
              final doctor = rawDoc.isNotEmpty ? rawDoc : 'Dr. Jeswin Jose BDS';
              final medHistory = _safeCell(r, colMedHist).isNotEmpty ? _safeCell(r, colMedHist) : 'None';
              final drugAllergies = _safeCell(r, colAllergies).isNotEmpty ? _safeCell(r, colAllergies) : 'None';
              final disease = _safeCell(r, colDisease);
              final treatVal = colTreatment >= 0 ? _safeCell(r, colTreatment) : disease;
              final treatNotes = treatVal.isNotEmpty ? treatVal : (disease.isNotEmpty ? disease : 'Clinical Dental Checkup');

              final cCharge = colConsult >= 0 ? (double.tryParse(_safeCell(r, colConsult).replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0) : 0.0;
              final xCharge = colXray >= 0 ? (double.tryParse(_safeCell(r, colXray).replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0) : 0.0;
              final pCharge = colPharm >= 0 ? (double.tryParse(_safeCell(r, colPharm).replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0) : 0.0;
              double tCharge = colTreatmentCharge >= 0 ? (double.tryParse(_safeCell(r, colTreatmentCharge).replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0) : 0.0;

              List<CustomChargeItem> customs = [];
              if (colCustom >= 0) {
                final rawCust = _safeCell(r, colCustom);
                if (rawCust.isNotEmpty) {
                  try {
                    final dec = jsonDecode(rawCust);
                    if (dec is List) {
                      for (final it in dec) {
                        if (it is Map) customs.add(CustomChargeItem.fromJson(Map<String, dynamic>.from(it)));
                      }
                    }
                  } catch (_) {}
                }
              }

              final custSum = customs.fold<double>(0.0, (s, c) => s + c.amount);
              final rawTotal = _safeCell(r, colTotal).replaceAll(RegExp(r'[^0-9.]'), '');
              final known = cCharge + xCharge + pCharge + custSum;
              double totalAmt = double.tryParse(rawTotal) ?? (known + tCharge);

              if (tCharge <= 0 && totalAmt > known) {
                tCharge = totalAmt - known;
              }

              final rawInv = _safeCell(r, colInv);
              final invNo = rawInv.isNotEmpty ? rawInv : 'INV-SHEET';

              final visitDate = timestamp.split(' ').first;
              final visit = VisitRecord(
                date: visitDate.isNotEmpty ? visitDate : '2026-10-14',
                doctor: doctor,
                notes: treatNotes,
                invoiceId: invNo,
                amount: totalAmt,
                consultationCharge: cCharge,
                xrayCharge: xCharge,
                pharmacyCharge: pCharge,
                treatmentCharge: tCharge,
                customCharges: customs,
              );

              final effectiveOp = rawOp.isNotEmpty ? rawOp : 'OP-${(name.hashCode.abs() % 900) + 100}';

              final existingIdx = csvPatients.indexWhere((p) {
                final pDigits = p.phone.replaceAll(RegExp(r'\D'), '');
                final curDigits = phone.replaceAll(RegExp(r'\D'), '');
                final phoneMatch = pDigits.isNotEmpty && curDigits.isNotEmpty &&
                    (pDigits == curDigits || (pDigits.length >= 10 && curDigits.length >= 10 && pDigits.endsWith(curDigits.substring(curDigits.length - 10))));
                final nameMatch = p.name.trim().toLowerCase() == name.trim().toLowerCase();
                final opMatch = rawOp.isNotEmpty && p.opNumber.isNotEmpty && p.opNumber.toLowerCase() == rawOp.toLowerCase();
                return (phoneMatch && nameMatch) || opMatch;
              });

              if (existingIdx >= 0) {
                final ex = csvPatients[existingIdx];
                final preservedOp = ex.opNumber.isNotEmpty ? ex.opNumber : effectiveOp;
                ex.visits.add(visit);
                csvPatients[existingIdx] = Patient(
                  id: ex.id,
                  opNumber: preservedOp,
                  name: ex.name,
                  phone: ex.phone,
                  email: ex.email,
                  dob: ex.dob,
                  gender: ex.gender,
                  doctor: ex.doctor,
                  medicalHistory: ex.medicalHistory,
                  drugAllergies: ex.drugAllergies,
                  diseaseHistory: ex.diseaseHistory,
                  registrationDate: ex.registrationDate,
                  totalVisits: ex.visits.length,
                  totalBilled: ex.totalBilled + totalAmt,
                  visits: ex.visits,
                );
              } else {
                csvPatients.add(Patient(
                  id: phone.isNotEmpty ? 'PAT-$phone' : 'PAT-${name.hashCode.abs()}',
                  opNumber: effectiveOp,
                  name: name,
                  phone: phone,
                  email: email,
                  dob: dob,
                  gender: gender,
                  doctor: doctor,
                  medicalHistory: medHistory,
                  drugAllergies: drugAllergies,
                  diseaseHistory: disease,
                  registrationDate: visitDate,
                  totalVisits: 1,
                  totalBilled: totalAmt,
                  visits: [visit],
                ));
              }
            }
            if (csvPatients.isNotEmpty) {
              patients.clear();
              patients.addAll(csvPatients);
            }
          }
        }
      } catch (_) {}
    }

    // 3. Fetch Google Sheet Appointments CSV directly + Apps Script status
    try {
      final res = await http.get(Uri.parse(appointmentsSheetCsvUrl)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final rows = _parseCsv(res.body);
        if (rows.isNotEmpty) {
          final headers = rows[0];
          final hasHeader = headers.any((h) =>
              h.toLowerCase().contains('appointment') ||
              h.toLowerCase().contains('name') ||
              h.toLowerCase().contains('phone'));

          final colId = _findCol(headers, ['appointment', 'id', 'booking'], 0);
          final colName = _findCol(headers, ['patient', 'name'], 1);
          final colPhone = _findCol(headers, ['phone', 'mobile'], 2);
          final colDate = _findCol(headers, ['date', 'day'], 4);
          final colTime = _findCol(headers, ['time', 'slot'], 5);
          final colDoctor = _findCol(headers, ['doctor'], 6);
          final colReason = _findCol(headers, ['reason', 'procedure', 'purpose'], 7);
          final colStatus = _findCol(headers, ['status'], 8);
          final colNotes = _findCol(headers, ['note', 'remark'], 11);

          final startIdx = hasHeader ? 1 : 0;
          for (int i = startIdx; i < rows.length; i++) {
            final r = rows[i];
            if (r.isEmpty) continue;
            final aptId = _safeCell(r, colId);
            if (aptId.toLowerCase().contains('appointment') && hasHeader) continue;
            final pName = _safeCell(r, colName);
            final phone = _safeCell(r, colPhone);
            if (pName.isEmpty && phone.isEmpty) continue;
            if (isDummyAppointment(aptId, pName, phone)) continue;

            final rawDate = _safeCell(r, colDate);
            final dateStr = rawDate.isNotEmpty ? rawDate : '2026-10-14';
            final rawTime = _safeCell(r, colTime);
            final timeSlot = rawTime.isNotEmpty ? rawTime : '10:00 AM';
            final rawDoc = _safeCell(r, colDoctor);
            final doctor = rawDoc.isNotEmpty ? rawDoc : 'Dr. Jeswin Jose BDS';
            final rawReason = _safeCell(r, colReason);
            final reason = rawReason.isNotEmpty ? rawReason : 'General Consultation & Checkup';
            final rawStatus = _safeCell(r, colStatus);
            final status = rawStatus.isNotEmpty ? rawStatus : 'Upcoming';
            final notes = _safeCell(r, colNotes);

            final apt = Appointment(
              id: aptId,
              patientName: pName,
              phone: phone,
              doctor: doctor,
              date: dateStr,
              timeSlot: timeSlot.contains('AM') || timeSlot.contains('PM') ? timeSlot : '$timeSlot AM',
              reason: reason,
              status: status == 'Scheduled' ? 'Upcoming' : status,
              notes: notes,
            );

            final existingIdx = appointments.indexWhere((a) => a.id == apt.id);
            if (existingIdx >= 0) {
              appointments[existingIdx] = apt;
            } else {
              appointments.add(apt);
            }
          }
        }
      }
    } catch (_) {}

    // Apps Script appointments for latest statuses
    try {
      final res = await http.get(Uri.parse('$defaultScriptUrl?action=getAppointments&type=all')).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final data = jsonDecode(res.body);
        if (data is Map && data['status'] == 'success' && data['data'] is List) {
          for (final item in data['data']) {
            final aptId = item['appointmentId']?.toString().trim() ?? '';
            final pName = item['patientName']?.toString().trim() ?? '';
            final phone = item['phone']?.toString().trim() ?? '';
            if (aptId.isEmpty || isDummyAppointment(aptId, pName, phone)) continue;

            final existingIdx = appointments.indexWhere((a) => a.id == aptId);
            if (existingIdx >= 0) {
              if (item['status'] != null) {
                final st = item['status'].toString().trim();
                appointments[existingIdx].status = st == 'Scheduled' ? 'Upcoming' : st;
              }
            }
          }
        }
      }
    } catch (_) {}

    // 4. Fetch Google Sheet Invoices CSV & Accounts
    try {
      final res = await http.get(Uri.parse(invoicesSheetCsvUrl)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final rows = _parseCsv(res.body);
        if (rows.isNotEmpty) {
          final headers = rows[0];
          final hasHeader = headers.any((h) =>
              h.toLowerCase().contains('invoice') ||
              h.toLowerCase().contains('name') ||
              h.toLowerCase().contains('bill') ||
              h.toLowerCase().contains('date'));

          final colId = _findCol(headers, ['invoice no', 'invoice number', 'invoice', 'inv', 'bill', 'id'], 0);
          final colOp = _findCol(headers, ['op number', 'op no', 'opnum', 'op#', 'op', 'patient id'], -1);
          final colDate = _findCol(headers, ['date', 'time', 'timestamp'], -1);
          final colName = _findCol(headers, ['patient name', 'full name', 'patient', 'name'], -1);
          final colPhone = _findCol(headers, ['phone', 'mobile', 'contact', 'cell'], -1);
          final colDoctor = _findCol(headers, ['doctor', 'dentist', 'attending', 'consulted'], -1, excludes: ['charge', 'fee', 'amount']);
          final colTreatment = _findCol(headers, ['treatment name', 'treatment procedure', 'treatment'], -1, excludes: ['charge', 'rate', 'nos', 'cost', 'fee', 'amount']);
          final colTreatmentCharge = _findCol(headers, ['treatment charge', 'procedure charge', 'treatment fee'], -1);
          final colTreatmentNos = _findCol(headers, ['treatment nos', 'nos', 'qty', 'quantity'], -1);
          final colTreatmentRate = _findCol(headers, ['treatment rate', 'rate', 'unit price'], -1);
          final colConsult = _findCol(headers, ['consultation charge', 'consult charge', 'consultation fee', 'consultation', 'consult'], -1, excludes: ['doctor', 'dentist']);
          final colXray = _findCol(headers, ['xray', 'x-ray'], -1);
          final colPharm = _findCol(headers, ['pharm', 'medicin', 'medicine'], -1);
          final colCustom = _findCol(headers, ['custom charges', 'custom', 'extra'], -1);
          final colTotal = _findCol(headers, ['total amount', 'total', 'amount', 'fee'], -1);
          final colPayMode = _findCol(headers, ['payment mode', 'payment', 'mode', 'method'], -1);
          final colAddress = _findCol(headers, ['address', 'place', 'location', 'city'], -1);

          final startIdx = hasHeader ? 1 : 0;
          for (int i = startIdx; i < rows.length; i++) {
            final r = rows[i];
            if (r.isEmpty) continue;

            final invId = _safeCell(r, colId);
            if (invId.toLowerCase().contains('invoice') && hasHeader) continue;

            // Handle column fallback if header is absent
            String rawOp = colOp >= 0 ? _safeCell(r, colOp) : '';
            String rawDate = colDate >= 0 ? _safeCell(r, colDate) : '';
            String pName = colName >= 0 ? _safeCell(r, colName) : '';
            String phone = colPhone >= 0 ? _safeCell(r, colPhone) : '';
            String rawDoc = colDoctor >= 0 ? _safeCell(r, colDoctor) : '';
            String rawTreatment = colTreatment >= 0 ? _safeCell(r, colTreatment) : '';
            String rawTreatmentCharge = colTreatmentCharge >= 0 ? _safeCell(r, colTreatmentCharge) : '';
            String rawTreatmentNos = colTreatmentNos >= 0 ? _safeCell(r, colTreatmentNos) : '';
            String rawTreatmentRate = colTreatmentRate >= 0 ? _safeCell(r, colTreatmentRate) : '';
            String rawConsult = colConsult >= 0 ? _safeCell(r, colConsult) : '';
            String rawXray = colXray >= 0 ? _safeCell(r, colXray) : '';
            String rawPharm = colPharm >= 0 ? _safeCell(r, colPharm) : '';
            String rawCustom = colCustom >= 0 ? _safeCell(r, colCustom) : '';
            String rawTotal = colTotal >= 0 ? _safeCell(r, colTotal) : '';
            String rawPayMode = colPayMode >= 0 ? _safeCell(r, colPayMode) : '';
            String rawAddress = colAddress >= 0 ? _safeCell(r, colAddress) : '';

            // Handle legacy 11 or 12 column format without headers
            if (!hasHeader) {
              if (r.length >= 12) {
                // 0: inv, 1: op, 2: date, 3: name, 4: phone, 5: doc, 6: consult, 7: xray, 8: pharm, 9: total, 10: mode
                rawOp = _safeCell(r, 1);
                rawDate = _safeCell(r, 2);
                pName = _safeCell(r, 3);
                phone = _safeCell(r, 4);
                rawDoc = _safeCell(r, 5);
                rawConsult = _safeCell(r, 6);
                rawXray = _safeCell(r, 7);
                rawPharm = _safeCell(r, 8);
                rawTotal = _safeCell(r, 9);
                rawPayMode = _safeCell(r, 10);
              } else if (r.length >= 10) {
                // 0: inv, 1: date, 2: name, 3: phone, 4: doc, 5: consult, 6: xray, 7: pharm, 8: total, 9: mode
                rawDate = _safeCell(r, 1);
                pName = _safeCell(r, 2);
                phone = _safeCell(r, 3);
                rawDoc = _safeCell(r, 4);
                rawConsult = _safeCell(r, 5);
                rawXray = _safeCell(r, 6);
                rawPharm = _safeCell(r, 7);
                rawTotal = _safeCell(r, 8);
                rawPayMode = _safeCell(r, 9);
              }
            }

            if (pName.isEmpty && phone.isEmpty && invId.isEmpty) continue;
            if (isDummyInvoice(invId, pName)) continue;

            String dateStr = rawDate;
            if (dateStr.isEmpty) dateStr = '2026-10-14';
            final dMatch = RegExp(r'^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})').firstMatch(dateStr);
            if (dMatch != null) {
              final day = dMatch.group(1)!.padLeft(2, '0');
              final month = dMatch.group(2)!.padLeft(2, '0');
              final year = dMatch.group(3)!;
              dateStr = '$year-$month-$day';
            } else if (dateStr.length >= 10 && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(dateStr)) {
              dateStr = dateStr.substring(0, 10);
            }

            final doctor = rawDoc.isNotEmpty ? rawDoc : 'Dr. Jeswin Jose BDS';
            final consult = double.tryParse(rawConsult.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
            final xray = double.tryParse(rawXray.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
            final pharm = double.tryParse(rawPharm.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
            final tCharge = double.tryParse(rawTreatmentCharge.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
            final tNos = int.tryParse(rawTreatmentNos.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1;
            final tRate = double.tryParse(rawTreatmentRate.replaceAll(RegExp(r'[^0-9.]'), '')) ?? (tNos > 0 && tCharge > 0 ? (tCharge / tNos) : tCharge);

            List<CustomChargeItem> customs = [];
            if (rawCustom.isNotEmpty) {
              try {
                final dec = jsonDecode(rawCustom);
                if (dec is List) {
                  for (final item in dec) {
                    if (item is Map) customs.add(CustomChargeItem.fromJson(Map<String, dynamic>.from(item)));
                  }
                }
              } catch (_) {}
            }

            final rawTot = double.tryParse(rawTotal.replaceAll(RegExp(r'[^0-9.]'), ''));
            final customSum = customs.fold<double>(0.0, (s, c) => s + c.amount);
            final total = (rawTot != null && rawTot > 0) ? rawTot : (consult + xray + pharm + tCharge + customSum);
            final payMode = rawPayMode.isNotEmpty ? rawPayMode : 'Cash';

            final knownCharges = consult + xray + pharm + customSum;
            double resolvedTreatmentCharge = tCharge;
            if (resolvedTreatmentCharge <= 0 && total > knownCharges) {
              resolvedTreatmentCharge = total - knownCharges;
            }
            String resolvedTreatment = rawTreatment;
            if (resolvedTreatment.isEmpty) {
              final cleanIId = invId.replaceAll(RegExp(r'^INV-'), '').toLowerCase().trim();
              for (final p in patients) {
                for (final v in p.visits) {
                  final cleanVId = v.invoiceId.replaceAll(RegExp(r'^INV-'), '').toLowerCase().trim();
                  if (cleanVId.isNotEmpty && cleanIId.isNotEmpty && (cleanVId == cleanIId || cleanIId.contains(cleanVId) || cleanVId.contains(cleanIId))) {
                    if (v.notes.isNotEmpty) resolvedTreatment = v.notes;
                    break;
                  }
                }
                if (resolvedTreatment.isNotEmpty) break;
              }
              if (resolvedTreatment.isEmpty) {
                final pMatch = patients.where((p) =>
                    (p.name.trim().toLowerCase() == pName.trim().toLowerCase()) ||
                    (phone.isNotEmpty && p.phone == phone));
                if (pMatch.isNotEmpty && pMatch.first.diseaseHistory.isNotEmpty) {
                  resolvedTreatment = pMatch.first.diseaseHistory;
                }
              }
            }
            if (resolvedTreatment.isEmpty) {
              resolvedTreatment = 'Dental Treatment & Procedure';
            }
            final resolvedRate = tRate > 0 ? tRate : (tNos > 0 ? (resolvedTreatmentCharge / tNos) : resolvedTreatmentCharge);

            final inv = Invoice(
              id: invId,
              patientName: pName,
              phone: phone,
              doctor: doctor,
              date: dateStr,
              address: rawAddress,
              opNumber: rawOp,
              consultationCharge: consult,
              xrayCharge: xray,
              pharmacyCharge: pharm,
              treatmentCharge: resolvedTreatmentCharge,
              treatment: resolvedTreatment,
              treatmentNos: tNos > 0 ? tNos : 1,
              treatmentRate: resolvedRate,
              customCharges: customs,
              totalAmount: total,
              paymentMode: payMode,
            );

            final existingIdx = invoices.indexWhere((it) => it.id.toLowerCase() == inv.id.toLowerCase());
            if (existingIdx >= 0) {
              final cur = invoices[existingIdx];
              invoices[existingIdx] = inv.copyWith(
                treatment: inv.treatment.isNotEmpty ? inv.treatment : cur.treatment,
                treatmentCharge: inv.treatmentCharge > 0 ? inv.treatmentCharge : cur.treatmentCharge,
                consultationCharge: inv.consultationCharge > 0 ? inv.consultationCharge : cur.consultationCharge,
                xrayCharge: inv.xrayCharge > 0 ? inv.xrayCharge : cur.xrayCharge,
                pharmacyCharge: inv.pharmacyCharge > 0 ? inv.pharmacyCharge : cur.pharmacyCharge,
                opNumber: inv.opNumber.isNotEmpty ? inv.opNumber : cur.opNumber,
                address: inv.address.isNotEmpty ? inv.address : cur.address,
                notes: inv.notes.isNotEmpty ? inv.notes : cur.notes,
                customCharges: inv.customCharges.isNotEmpty ? inv.customCharges : cur.customCharges,
              );
            } else {
              invoices.add(inv);
            }
          }
        }
      }
    } catch (_) {}

    // 5. Fetch Google Apps Script live Pharmacy Stock
    try {
      final res = await http.get(Uri.parse('$defaultScriptUrl?action=getPharmacyStock')).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final data = jsonDecode(res.body);
        if (data is Map && data['status'] == 'success' && data['data'] is List) {
          for (final it in data['data']) {
            final id = it['itemId']?.toString().trim() ?? '';
            final name = it['itemName']?.toString().trim() ?? '';
            if (id.isEmpty && name.isEmpty) continue;

            final invItem = InventoryItem(
              id: id.isNotEmpty ? id : 'MED-${inventory.length + 1001}',
              name: name,
              category: it['category']?.toString() ?? 'Medicines',
              batch: it['batchNo']?.toString() ?? 'AMX-2026-A1',
              expiryDate: it['expiryDate']?.toString() ?? '2027-12-31',
              unitPrice: (it['unitPrice'] as num?)?.toDouble() ?? 10.0,
              quantity: (it['quantity'] as num?)?.toInt() ?? 100,
              minStockThreshold: (it['minThreshold'] as num?)?.toInt() ?? 20,
            );

            final existingIdx = inventory.indexWhere((x) => x.id == invItem.id);
            if (existingIdx >= 0) {
              inventory[existingIdx] = invItem;
            } else {
              inventory.add(invItem);
            }
          }
        }
      }
    } catch (_) {}

    // Final strict filter: remove any dummy test data
    patients.removeWhere((p) => isDummyPatient(p.name, p.phone, p.id));
    appointments.removeWhere((a) => isDummyAppointment(a.id, a.patientName, a.phone));
    invoices.removeWhere((i) => isDummyInvoice(i.id, i.patientName));

    return {
      'patients': patients,
      'appointments': appointments,
      'invoices': invoices,
      'inventory': inventory,
    };
  }

  /// Alias for backward compatibility
  static Future<Map<String, dynamic>> fetchGoogleSheetData() async {
    return fetchCloudData();
  }
}
