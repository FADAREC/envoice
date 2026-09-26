import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  BusinessProfiles,
  Clients,
  Invoices,
  InvoiceItems,
  Payments,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
      );

  // ── Business profile ──────────────────────────────────────────

  Future<BusinessProfile?> getBusinessProfile() {
    return (select(businessProfiles)..limit(1)).getSingleOrNull();
  }

  Future<int> upsertBusinessProfile(BusinessProfilesCompanion data) async {
    final existing = await getBusinessProfile();
    if (existing == null) {
      return into(businessProfiles).insert(data);
    }
    return (update(businessProfiles)..where((t) => t.id.equals(existing.id)))
        .write(data.copyWith(updatedAt: Value(DateTime.now())));
  }

  /// Sequential invoice numbers: INV-0001, INV-0002, ...
  Future<String> allocateInvoiceNumber() async {
    final profile = await getBusinessProfile();
    final prefix = profile?.invoicePrefix ?? 'INV';
    final next = profile?.nextInvoiceNumber ?? 1;
    final number = '$prefix-${next.toString().padLeft(4, '0')}';

    if (profile != null) {
      await (update(businessProfiles)..where((t) => t.id.equals(profile.id)))
          .write(BusinessProfilesCompanion(
        nextInvoiceNumber: Value(next + 1),
        updatedAt: Value(DateTime.now()),
      ));
    } else {
      // Create a minimal profile so numbering still advances
      await into(businessProfiles).insert(BusinessProfilesCompanion.insert(
        companyName: 'My Business',
        nextInvoiceNumber: const Value(2),
      ));
    }

    return number;
  }

  // ── Clients ───────────────────────────────────────────────────

  Future<List<Client>> getAllClients() {
    return (select(clients)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Future<List<Client>> searchClients(String query) {
    final q = '%${query.toLowerCase()}%';
    return (select(clients)
          ..where((t) =>
              t.name.lower().like(q) |
              t.email.lower().like(q) |
              t.company.lower().like(q) |
              t.phone.like(q))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Future<Client?> getClient(String id) {
    return (select(clients)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<void> upsertClient(ClientsCompanion data) {
    return into(clients).insertOnConflictUpdate(data);
  }

  Future<void> deleteClient(String id) {
    return (delete(clients)..where((t) => t.id.equals(id))).go();
  }

  // ── Invoices ──────────────────────────────────────────────────

  Future<List<Invoice>> getAllInvoices() {
    return (select(invoices)
          ..orderBy([(t) => OrderingTerm.desc(t.issueDate)]))
        .get();
  }

  Future<List<Invoice>> getInvoicesByStatus(String status) {
    return (select(invoices)
          ..where((t) => t.status.equals(status))
          ..orderBy([(t) => OrderingTerm.desc(t.issueDate)]))
        .get();
  }

  Future<Invoice?> getInvoice(String id) {
    return (select(invoices)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<List<InvoiceItem>> getInvoiceItems(String invoiceId) {
    return (select(invoiceItems)
          ..where((t) => t.invoiceId.equals(invoiceId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  Future<void> upsertInvoice(
    InvoicesCompanion invoice,
    List<InvoiceItemsCompanion> items,
  ) async {
    await transaction(() async {
      await into(invoices).insertOnConflictUpdate(invoice);
      final invId = invoice.id.value;
      await (delete(invoiceItems)..where((t) => t.invoiceId.equals(invId))).go();
      for (final item in items) {
        await into(invoiceItems).insert(item);
      }
    });
  }

  Future<void> updateInvoiceStatus(String id, String status) {
    return (update(invoices)..where((t) => t.id.equals(id))).write(
      InvoicesCompanion(
        status: Value(status),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteInvoice(String id) async {
    await transaction(() async {
      await (delete(payments)..where((t) => t.invoiceId.equals(id))).go();
      await (delete(invoiceItems)..where((t) => t.invoiceId.equals(id))).go();
      await (delete(invoices)..where((t) => t.id.equals(id))).go();
    });
  }

  /// Effective display status: overdue wins when balance remains past due date.
  static String effectiveStatus(Invoice inv, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final remaining = inv.total - inv.amountPaid;
    if (inv.status == 'voided' || inv.status == 'paid' || inv.status == 'draft') {
      return inv.status;
    }
    if (inv.dueDate != null &&
        inv.dueDate!.isBefore(n) &&
        remaining > 0.001) {
      return 'overdue';
    }
    return inv.status;
  }

  // ── Payments (supports multiple partial payments per invoice) ─

  Future<List<Payment>> getPaymentsForInvoice(String invoiceId) {
    return (select(payments)
          ..where((t) => t.invoiceId.equals(invoiceId))
          ..orderBy([(t) => OrderingTerm.desc(t.paidAt)]))
        .get();
  }

  Future<void> addPayment(PaymentsCompanion payment) async {
    await transaction(() async {
      await into(payments).insert(payment);
      final invoiceId = payment.invoiceId.value;
      final all = await getPaymentsForInvoice(invoiceId);
      final paid = all.fold<double>(0, (s, p) => s + p.amount);
      final inv = await getInvoice(invoiceId);
      if (inv == null) return;

      String status;
      if (paid <= 0) {
        status = inv.status == 'draft' ? 'draft' : 'sent';
      } else if (paid + 0.001 >= inv.total) {
        status = 'paid';
      } else {
        status = 'partial';
      }

      await (update(invoices)..where((t) => t.id.equals(invoiceId))).write(
        InvoicesCompanion(
          amountPaid: Value(paid),
          status: Value(status),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  // ── Dashboard / money owed ────────────────────────────────────

  Future<DashboardStats> getDashboardStats() async {
    final all = await getAllInvoices();
    final clients = await getAllClients();
    final clientMap = {for (final c in clients) c.id: c};
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);

    double outstanding = 0;
    double paidThisMonth = 0;
    int overdueCount = 0;
    final debtors = <OutstandingEntry>[];

    for (final inv in all) {
      if (inv.status == 'voided' || inv.status == 'draft') continue;

      final remaining = inv.total - inv.amountPaid;
      if (remaining <= 0.001) {
        if (inv.status == 'paid' &&
            inv.updatedAt.isAfter(monthStart.subtract(const Duration(seconds: 1)))) {
          paidThisMonth += inv.total;
        }
        continue;
      }

      outstanding += remaining;
      final isOverdue = inv.dueDate != null && inv.dueDate!.isBefore(now);
      if (isOverdue) overdueCount++;

      final client = clientMap[inv.clientId];
      debtors.add(OutstandingEntry(
        invoice: inv,
        clientName: client?.name ?? 'Unknown',
        clientPhone: client?.phone,
        remaining: remaining,
        isOverdue: isOverdue,
      ));
    }

    // Oldest first (due date, then issue date)
    debtors.sort((a, b) {
      final ad = a.invoice.dueDate ?? a.invoice.issueDate;
      final bd = b.invoice.dueDate ?? b.invoice.issueDate;
      return ad.compareTo(bd);
    });

    return DashboardStats(
      outstanding: outstanding,
      paidThisMonth: paidThisMonth,
      overdueCount: overdueCount,
      invoiceCount: all.length,
      clientCount: clients.length,
      debtors: debtors,
    );
  }
}

class OutstandingEntry {
  final Invoice invoice;
  final String clientName;
  final String? clientPhone;
  final double remaining;
  final bool isOverdue;

  const OutstandingEntry({
    required this.invoice,
    required this.clientName,
    required this.clientPhone,
    required this.remaining,
    required this.isOverdue,
  });
}

class DashboardStats {
  final double outstanding;
  final double paidThisMonth;
  final int overdueCount;
  final int invoiceCount;
  final int clientCount;
  final List<OutstandingEntry> debtors;

  const DashboardStats({
    required this.outstanding,
    required this.paidThisMonth,
    required this.overdueCount,
    required this.invoiceCount,
    required this.clientCount,
    this.debtors = const [],
  });
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'envoice.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
