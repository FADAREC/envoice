import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// User-controlled backup. Clears "Clear cache" risk and phone-loss risk
/// only if the owner actually exports and stores the file somewhere safe
/// (Google Drive, WhatsApp to self, USB, etc.).
class BackupService {
  final AppDatabase db;

  BackupService(this.db);

  Future<Map<String, dynamic>> _snapshot() async {
    final profile = await db.getBusinessProfile();
    final clients = await db.getAllClients();
    final invoices = await db.getAllInvoices();

    final items = <Map<String, dynamic>>[];
    final payments = <Map<String, dynamic>>[];
    for (final inv in invoices) {
      final lineItems = await db.getInvoiceItems(inv.id);
      for (final li in lineItems) {
        items.add(_itemToJson(li));
      }
      final pays = await db.getPaymentsForInvoice(inv.id);
      for (final pay in pays) {
        payments.add(_paymentToJson(pay));
      }
    }

    return {
      'format': 'envoice-backup',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'business': profile == null ? null : _profileToJson(profile),
      'clients': clients.map(_clientToJson).toList(),
      'invoices': invoices.map(_invoiceToJson).toList(),
      'invoiceItems': items,
      'payments': payments,
    };
  }

  /// Writes a JSON backup and opens the system share sheet so the user
  /// can save to Drive, Files, WhatsApp, email, etc.
  Future<void> exportAndShare() async {
    final data = await _snapshot();
    final json = const JsonEncoder.withIndent('  ').convert(data);
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File(p.join(dir.path, 'envoice-backup-$stamp.json'));
    await file.writeAsString(json, flush: true);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json', name: p.basename(file.path))],
      subject: 'Envoice backup',
      text: 'Envoice offline backup. Keep this file somewhere safe.',
    );
  }

  /// Picks a backup file and restores. Replaces current local data.
  Future<int> importFromPicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      throw StateError('No file selected');
    }

    final file = result.files.single;
    final bytes = file.bytes;
    String raw;
    if (bytes != null) {
      raw = utf8.decode(bytes);
    } else if (file.path != null) {
      raw = await File(file.path!).readAsString();
    } else {
      throw StateError('Could not read backup file');
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Invalid backup file');
    }
    if (decoded['format'] != 'envoice-backup') {
      throw StateError('Not an Envoice backup');
    }

    return _restore(decoded);
  }

  Future<int> _restore(Map<String, dynamic> data) async {
    return db.transaction(() async {
      // Wipe existing (except we rebuild from backup)
      await db.customStatement('DELETE FROM payments');
      await db.customStatement('DELETE FROM invoice_items');
      await db.customStatement('DELETE FROM invoices');
      await db.customStatement('DELETE FROM clients');
      await db.customStatement('DELETE FROM business_profiles');

      final business = data['business'];
      if (business is Map<String, dynamic>) {
        await db.into(db.businessProfiles).insert(_profileFromJson(business));
      }

      final clients = data['clients'] as List<dynamic>? ?? [];
      for (final c in clients) {
        if (c is Map<String, dynamic>) {
          await db.into(db.clients).insert(_clientFromJson(c));
        }
      }

      final invoices = data['invoices'] as List<dynamic>? ?? [];
      for (final inv in invoices) {
        if (inv is Map<String, dynamic>) {
          await db.into(db.invoices).insert(_invoiceFromJson(inv));
        }
      }

      final items = data['invoiceItems'] as List<dynamic>? ?? [];
      for (final item in items) {
        if (item is Map<String, dynamic>) {
          await db.into(db.invoiceItems).insert(_itemFromJson(item));
        }
      }

      final payments = data['payments'] as List<dynamic>? ?? [];
      for (final pay in payments) {
        if (pay is Map<String, dynamic>) {
          await db.into(db.payments).insert(_paymentFromJson(pay));
        }
      }

      return invoices.length;
    });
  }

  Map<String, dynamic> _profileToJson(BusinessProfile p) => {
        'companyName': p.companyName,
        'email': p.email,
        'phone': p.phone,
        'addressLine1': p.addressLine1,
        'addressLine2': p.addressLine2,
        'city': p.city,
        'state': p.state,
        'country': p.country,
        'tin': p.tin,
        // logoPath is device-local; skip so restore still works on new phone
        'accentColor': p.accentColor,
        'invoicePrefix': p.invoicePrefix,
        'nextInvoiceNumber': p.nextInvoiceNumber,
        'defaultVatRate': p.defaultVatRate,
        'vatEnabledByDefault': p.vatEnabledByDefault,
        'currencyCode': p.currencyCode,
        'currencySymbol': p.currencySymbol,
      };

  BusinessProfilesCompanion _profileFromJson(Map<String, dynamic> m) {
    return BusinessProfilesCompanion.insert(
      companyName: m['companyName'] as String? ?? 'My Business',
      email: Value(m['email'] as String?),
      phone: Value(m['phone'] as String?),
      addressLine1: Value(m['addressLine1'] as String?),
      addressLine2: Value(m['addressLine2'] as String?),
      city: Value(m['city'] as String?),
      state: Value(m['state'] as String?),
      country: Value(m['country'] as String? ?? 'Nigeria'),
      tin: Value(m['tin'] as String?),
      accentColor: Value(m['accentColor'] as String? ?? '#0A0A0A'),
      invoicePrefix: Value(m['invoicePrefix'] as String? ?? 'INV'),
      nextInvoiceNumber: Value(m['nextInvoiceNumber'] as int? ?? 1),
      defaultVatRate: Value((m['defaultVatRate'] as num?)?.toDouble() ?? 7.5),
      vatEnabledByDefault: Value(m['vatEnabledByDefault'] as bool? ?? false),
      currencyCode: Value(m['currencyCode'] as String? ?? 'NGN'),
      currencySymbol: Value(m['currencySymbol'] as String? ?? '₦'),
    );
  }

  Map<String, dynamic> _clientToJson(Client c) => {
        'id': c.id,
        'name': c.name,
        'email': c.email,
        'phone': c.phone,
        'company': c.company,
        'addressLine1': c.addressLine1,
        'addressLine2': c.addressLine2,
        'city': c.city,
        'state': c.state,
        'notes': c.notes,
        'createdAt': c.createdAt.toIso8601String(),
        'updatedAt': c.updatedAt.toIso8601String(),
      };

  ClientsCompanion _clientFromJson(Map<String, dynamic> m) {
    return ClientsCompanion.insert(
      id: m['id'] as String,
      name: m['name'] as String,
      email: Value(m['email'] as String?),
      phone: Value(m['phone'] as String?),
      company: Value(m['company'] as String?),
      addressLine1: Value(m['addressLine1'] as String?),
      addressLine2: Value(m['addressLine2'] as String?),
      city: Value(m['city'] as String?),
      state: Value(m['state'] as String?),
      notes: Value(m['notes'] as String?),
      createdAt: Value(DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now()),
      updatedAt: Value(DateTime.tryParse(m['updatedAt'] as String? ?? '') ?? DateTime.now()),
    );
  }

  Map<String, dynamic> _invoiceToJson(Invoice i) => {
        'id': i.id,
        'number': i.number,
        'clientId': i.clientId,
        'status': i.status,
        'issueDate': i.issueDate.toIso8601String(),
        'dueDate': i.dueDate?.toIso8601String(),
        'currencyCode': i.currencyCode,
        'currencySymbol': i.currencySymbol,
        'subtotal': i.subtotal,
        'discountAmount': i.discountAmount,
        'vatRate': i.vatRate,
        'vatAmount': i.vatAmount,
        'total': i.total,
        'amountPaid': i.amountPaid,
        'notes': i.notes,
        'terms': i.terms,
        'createdAt': i.createdAt.toIso8601String(),
        'updatedAt': i.updatedAt.toIso8601String(),
      };

  InvoicesCompanion _invoiceFromJson(Map<String, dynamic> m) {
    return InvoicesCompanion.insert(
      id: m['id'] as String,
      number: m['number'] as String,
      clientId: m['clientId'] as String,
      status: Value(m['status'] as String? ?? 'draft'),
      issueDate: DateTime.tryParse(m['issueDate'] as String? ?? '') ?? DateTime.now(),
      dueDate: Value(
        m['dueDate'] != null ? DateTime.tryParse(m['dueDate'] as String) : null,
      ),
      currencyCode: Value(m['currencyCode'] as String? ?? 'NGN'),
      currencySymbol: Value(m['currencySymbol'] as String? ?? '₦'),
      subtotal: Value((m['subtotal'] as num?)?.toDouble() ?? 0),
      discountAmount: Value((m['discountAmount'] as num?)?.toDouble() ?? 0),
      vatRate: Value((m['vatRate'] as num?)?.toDouble() ?? 0),
      vatAmount: Value((m['vatAmount'] as num?)?.toDouble() ?? 0),
      total: Value((m['total'] as num?)?.toDouble() ?? 0),
      amountPaid: Value((m['amountPaid'] as num?)?.toDouble() ?? 0),
      notes: Value(m['notes'] as String?),
      terms: Value(m['terms'] as String?),
      createdAt: Value(DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now()),
      updatedAt: Value(DateTime.tryParse(m['updatedAt'] as String? ?? '') ?? DateTime.now()),
    );
  }

  Map<String, dynamic> _itemToJson(InvoiceItem i) => {
        'id': i.id,
        'invoiceId': i.invoiceId,
        'description': i.description,
        'quantity': i.quantity,
        'unitPrice': i.unitPrice,
        'amount': i.amount,
        'sortOrder': i.sortOrder,
      };

  InvoiceItemsCompanion _itemFromJson(Map<String, dynamic> m) {
    return InvoiceItemsCompanion.insert(
      id: m['id'] as String,
      invoiceId: m['invoiceId'] as String,
      description: m['description'] as String,
      quantity: Value((m['quantity'] as num?)?.toDouble() ?? 1),
      unitPrice: Value((m['unitPrice'] as num?)?.toDouble() ?? 0),
      amount: Value((m['amount'] as num?)?.toDouble() ?? 0),
      sortOrder: Value(m['sortOrder'] as int? ?? 0),
    );
  }

  Map<String, dynamic> _paymentToJson(Payment p) => {
        'id': p.id,
        'invoiceId': p.invoiceId,
        'amount': p.amount,
        'paidAt': p.paidAt.toIso8601String(),
        'method': p.method,
        'reference': p.reference,
        'notes': p.notes,
        'createdAt': p.createdAt.toIso8601String(),
      };

  PaymentsCompanion _paymentFromJson(Map<String, dynamic> m) {
    return PaymentsCompanion.insert(
      id: m['id'] as String,
      invoiceId: m['invoiceId'] as String,
      amount: (m['amount'] as num).toDouble(),
      paidAt: DateTime.tryParse(m['paidAt'] as String? ?? '') ?? DateTime.now(),
      method: Value(m['method'] as String?),
      reference: Value(m['reference'] as String?),
      notes: Value(m['notes'] as String?),
      createdAt: Value(DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now()),
    );
  }
}
