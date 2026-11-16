import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/patient.dart';
import '../models/appointment.dart';
import '../models/invoice.dart';
import '../models/inventory_item.dart';
import 'api_service.dart';

class StorageService extends ChangeNotifier {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  final List<Patient> _patients = [];
  final List<Appointment> _appointments = [];
  final List<Invoice> _invoices = [];
  final List<InventoryItem> _inventory = [];

  String _userRole = 'staff'; // Always opens in staff mode
  bool _initialized = false;

  List<Patient> get patients => List.unmodifiable(_patients);
  List<Appointment> get appointments => List.unmodifiable(_appointments);
  List<Invoice> get invoices => List.unmodifiable(_invoices);
  List<InventoryItem> get inventory => List.unmodifiable(_inventory);

  String get userRole => _userRole;
  bool get isAdmin => _userRole == 'admin';

  Future<void> setUserRole(String role) async {
    _userRole = (role == 'admin') ? 'admin' : 'staff';
    notifyListeners();
  }

  static bool isDummyPatient(String name, String phone, String id) {
    final n = name.trim().toLowerCase();
    final p = phone.trim();
    return n == 'test patient' || p == '133564456156' || id == 'PAT-133564456156';
  }

  static bool isDummyAppointment(String id, String name, String phone) {
    final n = name.trim().toLowerCase();
    return n == 'test patient' || id.contains('DUMMY');
  }

  static bool isDummyInvoice(String id, String name) {
    final n = name.trim().toLowerCase();
    return n == 'test patient' || id.contains('DUMMY');
  }

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      // App always opens in staff mode per clinic security requirements
      _userRole = 'staff';
      try {
        await prefs.remove('manjaly_user_role');
      } catch (_) {}

      final patientsJson = prefs.getString('manjaly_patients');
      final appointmentsJson = prefs.getString('manjaly_appointments');
      final invoicesJson = prefs.getString('manjaly_invoices');
      final inventoryJson = prefs.getString('manjaly_inventory');

      if (patientsJson != null && patientsJson.isNotEmpty) {
        final List list = jsonDecode(patientsJson);
        _patients.clear();
        for (final e in list) {
          final p = Patient.fromJson(e);
          if (!isDummyPatient(p.name, p.phone, p.id)) {
            _patients.add(p);
          }
        }
      } else {
        _patients.clear();
      }

      if (appointmentsJson != null && appointmentsJson.isNotEmpty) {
        final List list = jsonDecode(appointmentsJson);
        _appointments.clear();
        for (final e in list) {
          final a = Appointment.fromJson(e);
          if (!isDummyAppointment(a.id, a.patientName, a.phone)) {
            _appointments.add(a);
          }
        }
      } else {
        _appointments.clear();
      }

      if (invoicesJson != null && invoicesJson.isNotEmpty) {
        final List list = jsonDecode(invoicesJson);
        _invoices.clear();
        for (final e in list) {
          final i = Invoice.fromJson(e);
          if (!isDummyInvoice(i.id, i.patientName)) {
            _invoices.add(i);
          }
        }
      } else {
        _invoices.clear();
      }

      if (inventoryJson != null && inventoryJson.isNotEmpty) {
        final List list = jsonDecode(inventoryJson);
        _inventory.clear();
        _inventory.addAll(list.map((e) => InventoryItem.fromJson(e)));
      } else {
        _inventory.clear();
      }

      // Sanitize any previously cached dummy entries from local disk
      _patients.removeWhere((p) => isDummyPatient(p.name, p.phone, p.id));
      _appointments.removeWhere((a) => isDummyAppointment(a.id, a.patientName, a.phone));
      _invoices.removeWhere((i) => isDummyInvoice(i.id, i.patientName));
    } catch (e) {
      _patients.clear();
      _appointments.clear();
      _invoices.clear();
      _inventory.clear();
    }

    _initialized = true;
    notifyListeners();

    // Auto-sync with connected Google Sheet in background
    syncWithCloud();
  }

  /// Syncs app state directly with connected Google Sheet cloud database
  Future<bool> syncWithCloud() async {
    try {
      final data = await ApiService.fetchCloudData();
      final cloudPatients = data['patients'] as List<Patient>? ?? [];
      final cloudAppointments = data['appointments'] as List<Appointment>? ?? [];
      final cloudInvoices = data['invoices'] as List<Invoice>? ?? [];
      final cloudInventory = data['inventory'] as List<InventoryItem>? ?? [];

      // Purge any dummy data
      _patients.removeWhere((p) => isDummyPatient(p.name, p.phone, p.id));
      _appointments.removeWhere((a) => isDummyAppointment(a.id, a.patientName, a.phone));
      _invoices.removeWhere((i) => isDummyInvoice(i.id, i.patientName));

      // Sync Patients from Google Sheet - accept all sheet patients while preserving local additions
      final localCreatedPat = _patients.where((p) => !cloudPatients.any((cp) {
        final cpDigits = cp.phone.replaceAll(RegExp(r'\D'), '');
        final pDigits = p.phone.replaceAll(RegExp(r'\D'), '');
        final cpName = cp.name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
        final pName = p.name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
        final samePhone = cpDigits.isNotEmpty && pDigits.isNotEmpty && (cpDigits == pDigits || (cpDigits.length >= 10 && pDigits.length >= 10 && cpDigits.endsWith(pDigits.substring(pDigits.length - 10))));
        final sameName = cpName.isNotEmpty && pName.isNotEmpty && cpName == pName;
        final sameOp = cp.opNumber.isNotEmpty && p.opNumber.isNotEmpty && cp.opNumber.toLowerCase() == p.opNumber.toLowerCase();
        return (p.id == cp.id) || (samePhone && sameName) || sameOp;
      })).toList();
      _patients.clear();
      _patients.addAll(cloudPatients);
      for (final loc in localCreatedPat) {
        _patients.insert(0, loc);
      }

      // Sync Appointments from Google Sheet
      final localCreated = _appointments.where((a) => a.id.startsWith('APT-LOCAL-')).toList();
      _appointments.clear();
      _appointments.addAll(cloudAppointments);
      for (final loc in localCreated) {
        if (!_appointments.any((a) => a.id == loc.id)) {
          _appointments.insert(0, loc);
        }
      }

      // Helper function to clean invoice ID for reliable matching
      String cleanInvId(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'^inv-'), '');

      // Sync Invoices from Google Sheet while preserving and enriching all local invoices
      final mergedInvoices = <Invoice>[];
      final processedLocalIds = <String>{};

      for (final ci in cloudInvoices) {
        final cCleanId = cleanInvId(ci.id);
        final localIdx = _invoices.indexWhere((li) {
          final lCleanId = cleanInvId(li.id);
          final sameId = (cCleanId.isNotEmpty && lCleanId == cCleanId) || (li.id == ci.id);
          final samePatient = li.patientName.trim().toLowerCase() == ci.patientName.trim().toLowerCase() && li.date == ci.date;
          return sameId || samePatient;
        });

        if (localIdx >= 0) {
          final li = _invoices[localIdx];
          processedLocalIds.add(li.id);

          // Merge preserving the richer information
          mergedInvoices.add(li.copyWith(
            id: li.id.isNotEmpty ? li.id : ci.id,
            patientName: li.patientName.isNotEmpty ? li.patientName : ci.patientName,
            phone: li.phone.isNotEmpty ? li.phone : ci.phone,
            doctor: li.doctor.isNotEmpty && !li.doctor.contains('Attending') ? li.doctor : ci.doctor,
            date: li.date.isNotEmpty ? li.date : ci.date,
            address: li.address.isNotEmpty ? li.address : ci.address,
            opNumber: li.opNumber.isNotEmpty ? li.opNumber : ci.opNumber,
            consultationCharge: li.consultationCharge > 0 ? li.consultationCharge : ci.consultationCharge,
            xrayCharge: li.xrayCharge > 0 ? li.xrayCharge : ci.xrayCharge,
            pharmacyCharge: li.pharmacyCharge > 0 ? li.pharmacyCharge : ci.pharmacyCharge,
            treatmentCharge: li.treatmentCharge > 0 ? li.treatmentCharge : ci.treatmentCharge,
            treatment: li.treatment.isNotEmpty ? li.treatment : ci.treatment,
            treatmentNos: li.treatmentNos > 0 ? li.treatmentNos : ci.treatmentNos,
            treatmentRate: li.treatmentRate > 0 ? li.treatmentRate : ci.treatmentRate,
            customCharges: li.customCharges.isNotEmpty ? li.customCharges : ci.customCharges,
            totalAmount: li.totalAmount > 0 ? li.totalAmount : ci.totalAmount,
            paymentMode: li.paymentMode.isNotEmpty ? li.paymentMode : ci.paymentMode,
            notes: li.notes.isNotEmpty ? li.notes : ci.notes,
          ));
        } else {
          mergedInvoices.add(ci);
        }
      }

      // Add any local invoices that were not present in cloud
      for (final li in _invoices) {
        if (!processedLocalIds.contains(li.id)) {
          mergedInvoices.insert(0, li);
        }
      }

      // Cross-enrich any invoice missing opNumber, address, or treatment from patient directory
      for (int i = 0; i < mergedInvoices.length; i++) {
        var inv = mergedInvoices[i];
        final pMatch = _patients.where((p) {
          final pDigits = p.phone.replaceAll(RegExp(r'\D'), '');
          final iDigits = inv.phone.replaceAll(RegExp(r'\D'), '');
          final phoneSame = pDigits.isNotEmpty && iDigits.isNotEmpty && pDigits == iDigits;
          final nameSame = p.name.trim().toLowerCase() == inv.patientName.trim().toLowerCase();
          final opSame = p.opNumber.isNotEmpty && inv.opNumber.isNotEmpty && p.opNumber.toLowerCase() == inv.opNumber.toLowerCase();
          return (p.opNumber.isNotEmpty && inv.opNumber.isNotEmpty && opSame) || (phoneSame && nameSame) || nameSame;
        });

        if (pMatch.isNotEmpty) {
          final pat = pMatch.first;
          var updated = false;
          String newOp = inv.opNumber;
          String newAddr = inv.address;
          String newTreatment = inv.treatment;
          double newTreatmentCharge = inv.treatmentCharge;

          if (newOp.isEmpty && pat.opNumber.isNotEmpty) {
            newOp = pat.opNumber;
            updated = true;
          }
          if (newAddr.isEmpty && pat.address.isNotEmpty) {
            newAddr = pat.address;
            updated = true;
          }
          if (newTreatment.isEmpty) {
            final vMatch = pat.visits.where((v) => cleanInvId(v.invoiceId) == cleanInvId(inv.id) || v.date == inv.date);
            if (vMatch.isNotEmpty && vMatch.first.notes.isNotEmpty) {
              newTreatment = vMatch.first.notes;
              updated = true;
            } else if (pat.diseaseHistory.isNotEmpty) {
              newTreatment = pat.diseaseHistory;
              updated = true;
            }
          }
          if (newTreatmentCharge <= 0 && newTreatment.isNotEmpty) {
            final known = inv.consultationCharge + inv.xrayCharge + inv.pharmacyCharge + inv.customCharges.fold<double>(0.0, (s, c) => s + c.amount);
            if (inv.totalAmount > known) {
              newTreatmentCharge = inv.totalAmount - known;
              updated = true;
            }
          }

          if (updated) {
            mergedInvoices[i] = inv.copyWith(
              opNumber: newOp,
              address: newAddr,
              treatment: newTreatment,
              treatmentCharge: newTreatmentCharge,
            );
          }
        }
      }

      _invoices.clear();
      _invoices.addAll(mergedInvoices);

      // Sync Inventory from Google Sheet
      _inventory.clear();
      _inventory.addAll(cloudInventory);

      await _persist();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Cloud sync notice: $e');
      return false;
    }
  }

  /// Alias for backward compatibility
  Future<bool> syncWithGoogleSheet() async {
    return syncWithCloud();
  }

  // --- CRUD Operations ---

  Future<void> savePatient(Patient patient) async {
    final pDigits = patient.phone.replaceAll(RegExp(r'\D'), '');
    final pName = patient.name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final pOp = patient.opNumber.trim().toLowerCase();

    final idx = _patients.indexWhere((p) {
      if (p.id == patient.id) return true;
      final cDigits = p.phone.replaceAll(RegExp(r'\D'), '');
      final cName = p.name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      final cOp = p.opNumber.trim().toLowerCase();

      final opMatch = pOp.isNotEmpty && cOp.isNotEmpty && pOp == cOp;
      if (opMatch) return true;

      final phoneMatch = pDigits.isNotEmpty && cDigits.isNotEmpty &&
          (pDigits == cDigits || (pDigits.length >= 10 && cDigits.length >= 10 && pDigits.endsWith(cDigits.substring(cDigits.length - 10))));
      final nameMatch = pName.isNotEmpty && cName.isNotEmpty && pName == cName;

      return phoneMatch && nameMatch;
    });
    if (idx >= 0) {
      final existing = _patients[idx];
      // Keep the established OP for an existing patient.
      final effectiveOp = existing.opNumber.isNotEmpty
          ? existing.opNumber
          : (patient.opNumber.isNotEmpty ? patient.opNumber : 'OP-${existing.id}');
      _patients[idx] = Patient(
        id: existing.id.isNotEmpty ? existing.id : patient.id,
        opNumber: effectiveOp,
        name: patient.name.isNotEmpty ? patient.name : existing.name,
        phone: patient.phone.isNotEmpty ? patient.phone : existing.phone,
        email: patient.email.isNotEmpty ? patient.email : existing.email,
        dob: patient.dob.isNotEmpty ? patient.dob : existing.dob,
        age: patient.age > 0 ? patient.age : existing.age,
        gender: patient.gender.isNotEmpty ? patient.gender : existing.gender,
        address: patient.address.isNotEmpty ? patient.address : existing.address,
        doctor: patient.doctor.isNotEmpty ? patient.doctor : existing.doctor,
        medicalHistory: patient.medicalHistory.isNotEmpty ? patient.medicalHistory : existing.medicalHistory,
        drugAllergies: patient.drugAllergies.isNotEmpty ? patient.drugAllergies : existing.drugAllergies,
        diseaseHistory: patient.diseaseHistory.isNotEmpty ? patient.diseaseHistory : existing.diseaseHistory,
        registrationDate: patient.registrationDate.isNotEmpty ? patient.registrationDate : existing.registrationDate,
        totalVisits: existing.totalVisits + 1,
        totalBilled: existing.totalBilled + patient.totalBilled,
        visits: [...existing.visits, ...patient.visits],
      );
    } else {
      _patients.insert(0, patient);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> saveAppointment(Appointment apt) async {
    final idx = _appointments.indexWhere((a) => a.id == apt.id);
    if (idx >= 0) {
      _appointments[idx] = apt;
    } else {
      _appointments.insert(0, apt);
    }
    await _persist();
    notifyListeners();

    // Push to Google Cloud in background and sync
    ApiService.syncAppointmentOnline(apt).then((ok) {
      if (ok) syncWithCloud();
    });
  }

  Future<void> updateAppointmentStatus(String id, String newStatus) async {
    final apt = _appointments.firstWhere((a) => a.id == id, orElse: () => Appointment(id: '', patientName: '', phone: '', doctor: '', date: '', timeSlot: ''));
    if (apt.id.isNotEmpty) {
      apt.status = newStatus;
      await _persist();
      notifyListeners();

      // Push update to Google Cloud and sync
      ApiService.updateAppointmentStatusOnline(apt.id, newStatus).then((ok) {
        if (ok) syncWithCloud();
      });
    }
  }

  Future<void> rescheduleAppointment(String id, String newDate, String newTime, String doctor, String notes) async {
    final apt = _appointments.firstWhere((a) => a.id == id, orElse: () => Appointment(id: '', patientName: '', phone: '', doctor: '', date: '', timeSlot: ''));
    if (apt.id.isNotEmpty) {
      apt.date = newDate;
      apt.timeSlot = newTime;
      apt.notes = notes;
      await _persist();
      notifyListeners();

      // Push reschedule to Google Cloud and sync
      ApiService.rescheduleAppointmentOnline(apt.id, apt.phone, newDate, newTime, doctor, notes).then((ok) {
        if (ok) syncWithCloud();
      });
    }
  }

  Future<void> saveInvoice(Invoice invoice) async {
    final idx = _invoices.indexWhere((i) => i.id == invoice.id);
    if (idx >= 0) {
      _invoices[idx] = invoice;
    } else {
      _invoices.insert(0, invoice);
    }

    // Also update or link to existing patient
    final pIdx = _patients.indexWhere((p) =>
        (invoice.phone.isNotEmpty && p.phone == invoice.phone) ||
        (invoice.patientName.isNotEmpty && p.name.toLowerCase() == invoice.patientName.toLowerCase()));
    if (pIdx >= 0) {
      final existingVisitIdx = _patients[pIdx].visits.indexWhere((v) => v.invoiceId == invoice.id);
      if (existingVisitIdx < 0) {
        _patients[pIdx].totalVisits += 1;
        _patients[pIdx].totalBilled += invoice.totalAmount;
        _patients[pIdx].visits.insert(0, VisitRecord(
          date: invoice.date,
          doctor: invoice.doctor,
          notes: invoice.notes.isNotEmpty ? invoice.notes : (invoice.treatment.isNotEmpty ? invoice.treatment : 'Clinical consultation & billing'),
          invoiceId: invoice.id,
          amount: invoice.totalAmount,
        ));
      }
    }

    await _persist();
    notifyListeners();
  }

  Future<void> adjustStock(String itemId, int delta) async {
    final idx = _inventory.indexWhere((i) => i.id == itemId);
    if (idx >= 0) {
      final current = _inventory[idx].quantity;
      final updated = (current + delta).clamp(0, 99999);
      _inventory[idx].quantity = updated;
      await _persist();
      notifyListeners();
    }
  }

  Future<void> saveInventoryItem(InventoryItem item) async {
    final idx = _inventory.indexWhere((i) => i.id == item.id);
    if (idx >= 0) {
      _inventory[idx] = item;
    } else {
      _inventory.insert(0, item);
    }
    await _persist();
    notifyListeners();
  }

  // --- Financial Analytics Calculations ---

  Map<String, dynamic> getAccountsSummary(String period) {
    // Periods: 'today', 'week', 'month', 'all'
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    List<Invoice> filteredInvoices = [];

    if (period == 'today') {
      filteredInvoices = _invoices.where((i) => i.date == todayStr).toList();
    } else if (period == 'week') {
      final sevenDaysAgo = now.subtract(const Duration(days: 7));
      filteredInvoices = _invoices.where((i) {
        try {
          final dt = DateTime.parse(i.date);
          return dt.isAfter(sevenDaysAgo) && dt.isBefore(now.add(const Duration(days: 1)));
        } catch (_) {
          return false;
        }
      }).toList();
    } else if (period == 'month') {
      final monthPrefix = DateFormat('yyyy-MM').format(now);
      filteredInvoices = _invoices.where((i) => i.date.startsWith(monthPrefix)).toList();
    } else {
      filteredInvoices = List.from(_invoices);
    }

    double totalRevenue = 0.0;
    double consultationTotal = 0.0;
    double xrayTotal = 0.0;
    double pharmacyTotal = 0.0;

    double cashTotal = 0.0;
    double upiTotal = 0.0;
    double cardTotal = 0.0;
    double pendingTotal = 0.0;

    for (var inv in filteredInvoices) {
      totalRevenue += inv.totalAmount;
      consultationTotal += inv.consultationCharge;
      xrayTotal += inv.xrayCharge;
      pharmacyTotal += inv.pharmacyCharge;

      final mode = inv.paymentMode.toLowerCase();
      if (mode.contains('upi') || mode.contains('online')) {
        upiTotal += inv.totalAmount;
      } else if (mode.contains('card')) {
        cardTotal += inv.totalAmount;
      } else if (mode.contains('pending')) {
        pendingTotal += inv.totalAmount;
      } else {
        cashTotal += inv.totalAmount;
      }
    }

    // Overall metrics for the 4 stat cards
    double dailyTotal = 0;
    int dailyVisits = 0;
    double weeklyTotal = 0;
    int weeklyVisits = 0;
    double monthlyTotal = 0;
    int monthlyVisits = 0;
    double lifetimeTotal = 0;
    int lifetimeVisits = _invoices.length;

    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    final monthPrefix = DateFormat('yyyy-MM').format(now);

    for (var inv in _invoices) {
      lifetimeTotal += inv.totalAmount;
      if (inv.date == todayStr) {
        dailyTotal += inv.totalAmount;
        dailyVisits++;
      }
      try {
        final dt = DateTime.parse(inv.date);
        if (dt.isAfter(sevenDaysAgo) && dt.isBefore(now.add(const Duration(days: 1)))) {
          weeklyTotal += inv.totalAmount;
          weeklyVisits++;
        }
      } catch (_) {}
      if (inv.date.startsWith(monthPrefix)) {
        monthlyTotal += inv.totalAmount;
        monthlyVisits++;
      }
    }

    return {
      'dailyTotal': dailyTotal,
      'dailyVisits': dailyVisits,
      'weeklyTotal': weeklyTotal,
      'weeklyVisits': weeklyVisits,
      'monthlyTotal': monthlyTotal,
      'monthlyVisits': monthlyVisits,
      'lifetimeTotal': lifetimeTotal,
      'lifetimeVisits': lifetimeVisits,
      // Active period breakdown
      'filteredRevenue': totalRevenue,
      'filteredVisits': filteredInvoices.length,
      'consultationTotal': consultationTotal,
      'xrayTotal': xrayTotal,
      'pharmacyTotal': pharmacyTotal,
      'cashTotal': cashTotal,
      'upiTotal': upiTotal,
      'cardTotal': cardTotal,
      'pendingTotal': pendingTotal,
      'invoices': filteredInvoices,
    };
  }

  // Stock summary
  Map<String, dynamic> getStockSummary() {
    int totalItems = _inventory.length;
    int lowStockCount = _inventory.where((i) => i.isLowStock).length;
    int expiringSoonCount = _inventory.where((i) => i.isExpiringSoon).length;
    double totalValuation = _inventory.fold(0.0, (acc, i) => acc + (i.unitPrice * i.quantity));

    return {
      'totalItems': totalItems,
      'lowStockCount': lowStockCount,
      'expiringSoonCount': expiringSoonCount,
      'totalValuation': totalValuation,
    };
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('manjaly_patients', jsonEncode(_patients.map((p) => p.toJson()).toList()));
      await prefs.setString('manjaly_appointments', jsonEncode(_appointments.map((a) => a.toJson()).toList()));
      await prefs.setString('manjaly_invoices', jsonEncode(_invoices.map((i) => i.toJson()).toList()));
      await prefs.setString('manjaly_inventory', jsonEncode(_inventory.map((i) => i.toJson()).toList()));
    } catch (e) {
      debugPrint('Persistence error: $e');
    }
  }
}
