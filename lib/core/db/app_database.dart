import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  BusinessProfiles,
  Clients,
  Invoices,
  InvoiceItems,
  Payments,
  SavedItems,
  CatalogItems,
  Orders,
  OrderItems,
  OrderPayments,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await seedDefaultCatalog();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(savedItems);
          }
          if (from < 3) {
            await m.addColumn(businessProfiles, businessProfiles.bankName);
            await m.addColumn(businessProfiles, businessProfiles.bankAccountName);
            await m.addColumn(
                businessProfiles, businessProfiles.bankAccountNumber);
          }
          if (from < 4) {
            await m.addColumn(businessProfiles, businessProfiles.branchPrefix);
            await m.addColumn(businessProfiles, businessProfiles.nextTagNumber);
            await m.createTable(catalogItems);
            await m.createTable(orders);
            await m.createTable(orderItems);
            await m.createTable(orderPayments);
            await seedDefaultCatalog();
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> seedDefaultCatalog() async {
    final existing = await (select(catalogItems)..limit(1)).get();
    if (existing.isNotEmpty) return;

    const uuid = Uuid();
    const rows = <(String, double?, double?, int)>[
      ('Shirt / top', 0, 0, 10),
      ('Trouser', 0, 0, 20),
      ('Native wear (senator, agbada)', 0, 0, 30),
      ('Suit (2-piece)', null, 0, 40),
      ('Dress / gown', 0, 0, 50),
      ('Duvet / bedspread', 0, 0, 60),
      ('Bedsheet / towel', 0, 0, 70),
      ('Curtain (per panel)', null, 0, 80),
    ];

    for (final (name, wash, dry, sort) in rows) {
      if (wash != null) {
        await into(catalogItems).insert(CatalogItemsCompanion.insert(
          id: uuid.v4(),
          name: name,
          serviceType: 'wash_fold',
          unitPrice: Value(wash),
          sortOrder: Value(sort),
        ));
      }
      if (dry != null) {
        await into(catalogItems).insert(CatalogItemsCompanion.insert(
          id: uuid.v4(),
          name: name,
          serviceType: 'dry_clean',
          unitPrice: Value(dry),
          sortOrder: Value(sort + 1),
        ));
      }
    }
  }

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

  Future<List<Client>> getAllClients() {
    return (select(clients)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();
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

  Future<bool> deleteClientIfUnused(String id) async {
    final linkedInv =
        await (select(invoices)..where((t) => t.clientId.equals(id))).get();
    if (linkedInv.isNotEmpty) return false;
    final linkedOrd =
        await (select(orders)..where((t) => t.clientId.equals(id))).get();
    if (linkedOrd.isNotEmpty) return false;
    await (delete(clients)..where((t) => t.id.equals(id))).go();
    return true;
  }

  Future<int> countInvoicesForClient(String clientId) async {
    final rows = await (select(invoices)
          ..where((t) => t.clientId.equals(clientId)))
        .get();
    return rows.length;
  }

  Future<List<CatalogItem>> getActiveCatalog() {
    return (select(catalogItems)
          ..where((t) => t.active.equals(true))
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.name),
          ]))
        .get();
  }

  Future<List<CatalogItem>> getAllCatalog() {
    return (select(catalogItems)
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.name),
          ]))
        .get();
  }

  Future<void> upsertCatalogItem(CatalogItemsCompanion data) {
    return into(catalogItems).insertOnConflictUpdate(data);
  }

  Future<void> deleteCatalogItem(String id) {
    return (delete(catalogItems)..where((t) => t.id.equals(id))).go();
  }

  Future<List<Order>> getAllOrders() {
    return (select(orders)
          ..orderBy([(t) => OrderingTerm.desc(t.dropoffAt)]))
        .get();
  }

  Future<List<Order>> getOrdersByWorkflow(String status) {
    return (select(orders)
          ..where((t) => t.workflowStatus.equals(status))
          ..orderBy([(t) => OrderingTerm.desc(t.dropoffAt)]))
        .get();
  }

  Future<Order?> getOrder(String id) {
    return (select(orders)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<Order?> getOrderByTag(String tag) {
    return (select(orders)..where((t) => t.tagNumber.equals(tag)))
        .getSingleOrNull();
  }

  Future<List<OrderItem>> getOrderItems(String orderId) {
    return (select(orderItems)
          ..where((t) => t.orderId.equals(orderId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  Future<String> createOrderWithTag({
    required OrdersCompanion orderWithoutTag,
    required List<OrderItemsCompanion> items,
  }) async {
    return transaction(() async {
      final profile = await getBusinessProfile();
      final prefix = (profile?.branchPrefix ?? 'M').trim().toUpperCase();
      final next = profile?.nextTagNumber ?? 1;
      final tag = '$prefix-${next.toString().padLeft(5, '0')}';

      if (profile != null) {
        await (update(businessProfiles)..where((t) => t.id.equals(profile.id)))
            .write(BusinessProfilesCompanion(
          nextTagNumber: Value(next + 1),
          updatedAt: Value(DateTime.now()),
        ));
      } else {
        await into(businessProfiles).insert(BusinessProfilesCompanion.insert(
          companyName: 'My Laundry',
          branchPrefix: Value(prefix),
          nextTagNumber: const Value(2),
        ));
      }

      final ord = orderWithoutTag.copyWith(tagNumber: Value(tag));
      await into(orders).insertOnConflictUpdate(ord);
      final orderId = ord.id.value;
      await (delete(orderItems)..where((t) => t.orderId.equals(orderId))).go();
      for (final item in items) {
        await into(orderItems).insert(
          item.copyWith(orderId: Value(orderId)),
        );
      }
      return tag;
    });
  }

  Future<void> updateOrder(
    OrdersCompanion order,
    List<OrderItemsCompanion> items,
  ) async {
    await transaction(() async {
      await into(orders).insertOnConflictUpdate(order);
      final orderId = order.id.value;
      await (delete(orderItems)..where((t) => t.orderId.equals(orderId))).go();
      for (final item in items) {
        await into(orderItems).insert(item);
      }
    });
  }

  Future<void> updateOrderWorkflow(String id, String status) {
    return (update(orders)..where((t) => t.id.equals(id))).write(
      OrdersCompanion(
        workflowStatus: Value(status),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteOrder(String id) async {
    await transaction(() async {
      await (delete(orderPayments)..where((t) => t.orderId.equals(id))).go();
      await (delete(orderItems)..where((t) => t.orderId.equals(id))).go();
      await (delete(orders)..where((t) => t.id.equals(id))).go();
    });
  }

  Future<List<OrderPayment>> getPaymentsForOrder(String orderId) {
    return (select(orderPayments)
          ..where((t) => t.orderId.equals(orderId))
          ..orderBy([(t) => OrderingTerm.desc(t.paidAt)]))
        .get();
  }

  Future<void> addOrderPayment(OrderPaymentsCompanion payment) async {
    await transaction(() async {
      await into(orderPayments).insert(payment);
      await _recomputeOrderPaid(payment.orderId.value);
    });
  }

  Future<void> deleteOrderPayment(String paymentId, String orderId) async {
    await transaction(() async {
      await (delete(orderPayments)..where((t) => t.id.equals(paymentId))).go();
      await _recomputeOrderPaid(orderId);
    });
  }

  Future<void> _recomputeOrderPaid(String orderId) async {
    final all = await getPaymentsForOrder(orderId);
    final paid = all.fold<double>(0, (s, p) => s + p.amount);
    final ord = await getOrder(orderId);
    if (ord == null) return;

    String paymentStatus;
    if (paid <= 0) {
      paymentStatus = 'unpaid';
    } else if (paid + 0.001 >= ord.total) {
      paymentStatus = 'paid';
    } else {
      paymentStatus = 'partial';
    }

    await (update(orders)..where((t) => t.id.equals(orderId))).write(
      OrdersCompanion(
        amountPaid: Value(paid),
        paymentStatus: Value(paymentStatus),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<String> buildDailySummaryText({DateTime? day}) async {
    final d = day ?? DateTime.now();
    final start = DateTime(d.year, d.month, d.day);
    final end = start.add(const Duration(days: 1));
    final all = await getAllOrders();
    final today = all
        .where((o) =>
            !o.dropoffAt.isBefore(start) && o.dropoffAt.isBefore(end))
        .toList();

    double sales = 0;
    double paid = 0;
    int unpaid = 0;
    int ready = 0;
    for (final o in today) {
      sales += o.total;
      paid += o.amountPaid;
      if (o.paymentStatus != 'paid') unpaid++;
      if (o.workflowStatus == 'ready') ready++;
    }

    final profile = await getBusinessProfile();
    final name = profile?.companyName ?? 'Laundry';
    final prefix = profile?.branchPrefix ?? 'M';
    final symbol = profile?.currencySymbol ?? '₦';

    final buf = StringBuffer();
    buf.writeln('$name ($prefix) - daily summary');
    buf.writeln(
        '${start.day.toString().padLeft(2, '0')}/${start.month.toString().padLeft(2, '0')}/${start.year}');
    buf.writeln('Orders: ${today.length}');
    buf.writeln('Sales: $symbol${sales.toStringAsFixed(0)}');
    buf.writeln('Collected: $symbol${paid.toStringAsFixed(0)}');
    buf.writeln('Unpaid orders: $unpaid');
    buf.writeln('Ready for pickup: $ready');
    return buf.toString();
  }

  Future<List<SavedItem>> searchSavedItems(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return (select(savedItems)
            ..orderBy([
              (t) => OrderingTerm.desc(t.timesUsed),
              (t) => OrderingTerm.desc(t.updatedAt),
            ])
            ..limit(20))
          .get();
    }
    return (select(savedItems)
          ..where((t) => t.description.lower().like('%$q%'))
          ..orderBy([
            (t) => OrderingTerm.desc(t.timesUsed),
            (t) => OrderingTerm.desc(t.updatedAt),
          ])
          ..limit(12))
        .get();
  }

  Future<void> rememberSavedItem({
    required String description,
    required double unitPrice,
  }) async {
    final desc = description.trim();
    if (desc.isEmpty) return;
    final existing = await (select(savedItems)
          ..where((t) => t.description.lower().equals(desc.toLowerCase())))
        .getSingleOrNull();
    if (existing != null) {
      await (update(savedItems)..where((t) => t.id.equals(existing.id))).write(
        SavedItemsCompanion(
          unitPrice: Value(unitPrice),
          timesUsed: Value(existing.timesUsed + 1),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } else {
      await into(savedItems).insert(SavedItemsCompanion.insert(
        id: const Uuid().v4(),
        description: desc,
        unitPrice: Value(unitPrice),
      ));
    }
  }

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

  Future<String> createInvoiceWithNumber({
    required InvoicesCompanion invoiceWithoutNumber,
    required List<InvoiceItemsCompanion> items,
  }) async {
    return transaction(() async {
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
        await into(businessProfiles).insert(BusinessProfilesCompanion.insert(
          companyName: 'My Business',
          nextInvoiceNumber: const Value(2),
        ));
      }

      final inv = invoiceWithoutNumber.copyWith(number: Value(number));
      await into(invoices).insertOnConflictUpdate(inv);
      final invId = inv.id.value;
      await (delete(invoiceItems)..where((t) => t.invoiceId.equals(invId))).go();
      for (final item in items) {
        await into(invoiceItems).insert(
          item.copyWith(invoiceId: Value(invId)),
        );
        await rememberSavedItem(
          description: item.description.value,
          unitPrice: item.unitPrice.value,
        );
      }
      return number;
    });
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
        await rememberSavedItem(
          description: item.description.value,
          unitPrice: item.unitPrice.value,
        );
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

  static String effectiveStatus(Invoice inv, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final remaining = inv.total - inv.amountPaid;
    if (inv.status == 'voided' ||
        inv.status == 'paid' ||
        inv.status == 'draft') {
      return inv.status;
    }
    if (inv.dueDate != null &&
        inv.dueDate!.isBefore(n) &&
        remaining > 0.001) {
      return 'overdue';
    }
    return inv.status;
  }

  Future<List<Payment>> getPaymentsForInvoice(String invoiceId) {
    return (select(payments)
          ..where((t) => t.invoiceId.equals(invoiceId))
          ..orderBy([(t) => OrderingTerm.desc(t.paidAt)]))
        .get();
  }

  Future<void> addPayment(PaymentsCompanion payment) async {
    await transaction(() async {
      await into(payments).insert(payment);
      await _recomputePaid(payment.invoiceId.value);
    });
  }

  Future<void> deletePayment(String paymentId, String invoiceId) async {
    await transaction(() async {
      await (delete(payments)..where((t) => t.id.equals(paymentId))).go();
      await _recomputePaid(invoiceId);
    });
  }

  Future<void> _recomputePaid(String invoiceId) async {
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
  }

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
            inv.updatedAt
                .isAfter(monthStart.subtract(const Duration(seconds: 1)))) {
          paidThisMonth += inv.total;
        }
        continue;
      }

      outstanding += remaining;
      final isOverdue = effectiveStatus(inv, now: now) == 'overdue';
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
