import 'package:drift/drift.dart';

/// Single-row business profile. Company brand that appears on every document.
class BusinessProfiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get companyName => text().withLength(min: 1, max: 200)();
  TextColumn get email => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get addressLine1 => text().nullable()();
  TextColumn get addressLine2 => text().nullable()();
  TextColumn get city => text().nullable()();
  TextColumn get state => text().nullable()();
  TextColumn get country => text().withDefault(const Constant('Nigeria'))();

  TextColumn get tin => text().nullable()();
  TextColumn get logoPath => text().nullable()();

  TextColumn get accentColor => text().withDefault(const Constant('#0A0A0A'))();
  TextColumn get invoicePrefix => text().withDefault(const Constant('INV'))();
  IntColumn get nextInvoiceNumber => integer().withDefault(const Constant(1))();

  /// Branch tag prefix for Stage 1 (hardcoded per install): M = mainland, I = island.
  TextColumn get branchPrefix => text().withDefault(const Constant('M'))();
  IntColumn get nextTagNumber => integer().withDefault(const Constant(1))();

  RealColumn get defaultVatRate => real().withDefault(const Constant(7.5))();
  BoolColumn get vatEnabledByDefault =>
      boolean().withDefault(const Constant(false))();
  TextColumn get currencyCode => text().withDefault(const Constant('NGN'))();
  TextColumn get currencySymbol => text().withDefault(const Constant('₦'))();

  TextColumn get bankName => text().nullable()();
  TextColumn get bankAccountName => text().nullable()();
  TextColumn get bankAccountNumber => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class Clients extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get email => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get company => text().nullable()();
  TextColumn get addressLine1 => text().nullable()();
  TextColumn get addressLine2 => text().nullable()();
  TextColumn get city => text().nullable()();
  TextColumn get state => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Legacy invoice path (kept for existing data). New laundry flow uses Orders.
class Invoices extends Table {
  TextColumn get id => text()();
  TextColumn get number => text()();
  TextColumn get clientId => text().references(Clients, #id)();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  DateTimeColumn get issueDate => dateTime()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  TextColumn get currencyCode => text().withDefault(const Constant('NGN'))();
  TextColumn get currencySymbol => text().withDefault(const Constant('₦'))();
  RealColumn get subtotal => real().withDefault(const Constant(0))();
  RealColumn get discountAmount => real().withDefault(const Constant(0))();
  RealColumn get vatRate => real().withDefault(const Constant(0))();
  RealColumn get vatAmount => real().withDefault(const Constant(0))();
  RealColumn get total => real().withDefault(const Constant(0))();
  RealColumn get amountPaid => real().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  TextColumn get terms => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class InvoiceItems extends Table {
  TextColumn get id => text()();
  TextColumn get invoiceId => text().references(Invoices, #id)();
  TextColumn get description => text()();
  RealColumn get quantity => real().withDefault(const Constant(1))();
  RealColumn get unitPrice => real().withDefault(const Constant(0))();
  RealColumn get amount => real().withDefault(const Constant(0))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class Payments extends Table {
  TextColumn get id => text()();
  TextColumn get invoiceId => text().references(Invoices, #id)();
  RealColumn get amount => real()();
  DateTimeColumn get paidAt => dateTime()();
  TextColumn get method => text().nullable()();
  TextColumn get reference => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Legacy free-text saved lines from the old invoice editor.
class SavedItems extends Table {
  TextColumn get id => text()();
  TextColumn get description => text()();
  RealColumn get unitPrice => real().withDefault(const Constant(0))();
  IntColumn get timesUsed => integer().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Laundry price catalog: price is keyed by item name + service type.
/// serviceType: wash_fold | dry_clean
class CatalogItems extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get serviceType => text()();
  RealColumn get unitPrice => real().withDefault(const Constant(0))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Laundry order (internal record). Tag number is what the customer sees.
/// workflowStatus: received | washing | ready | collected
/// paymentStatus: unpaid | partial | paid
class Orders extends Table {
  TextColumn get id => text()();
  TextColumn get tagNumber => text()();
  TextColumn get clientId => text().references(Clients, #id)();
  TextColumn get workflowStatus =>
      text().withDefault(const Constant('received'))();
  TextColumn get paymentStatus =>
      text().withDefault(const Constant('unpaid'))();
  DateTimeColumn get dropoffAt => dateTime()();
  DateTimeColumn get expectedPickup => dateTime().nullable()();
  TextColumn get currencyCode => text().withDefault(const Constant('NGN'))();
  TextColumn get currencySymbol => text().withDefault(const Constant('₦'))();
  RealColumn get subtotal => real().withDefault(const Constant(0))();
  RealColumn get discountAmount => real().withDefault(const Constant(0))();
  RealColumn get total => real().withDefault(const Constant(0))();
  RealColumn get amountPaid => real().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class OrderItems extends Table {
  TextColumn get id => text()();
  TextColumn get orderId => text().references(Orders, #id)();
  TextColumn get catalogItemId => text().nullable()();
  TextColumn get description => text()();
  TextColumn get serviceType => text()();
  RealColumn get quantity => real().withDefault(const Constant(1))();
  RealColumn get unitPrice => real().withDefault(const Constant(0))();
  RealColumn get amount => real().withDefault(const Constant(0))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class OrderPayments extends Table {
  TextColumn get id => text()();
  TextColumn get orderId => text().references(Orders, #id)();
  RealColumn get amount => real()();
  DateTimeColumn get paidAt => dateTime()();
  TextColumn get method => text().nullable()();
  TextColumn get reference => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
