import 'package:drift/drift.dart';

/// Single-row business profile. Company brand that appears on every invoice.
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
  /// Tax ID
  TextColumn get tin => text().nullable()();
  /// Local file path to logo image
  TextColumn get logoPath => text().nullable()();
  TextColumn get accentColor => text().withDefault(const Constant('#0A0A0A'))();
  TextColumn get invoicePrefix => text().withDefault(const Constant('INV'))();
  IntColumn get nextInvoiceNumber => integer().withDefault(const Constant(1))();
  /// Nigeria VAT default rate
  RealColumn get defaultVatRate => real().withDefault(const Constant(7.5))();
  BoolColumn get vatEnabledByDefault =>
      boolean().withDefault(const Constant(false))();
  TextColumn get currencyCode => text().withDefault(const Constant('NGN'))();
  TextColumn get currencySymbol => text().withDefault(const Constant('₦'))();
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

/// Status values: draft | sent | paid | partial | overdue | voided
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
  /// transfer, cash, card, pos
  TextColumn get method => text().nullable()();
  TextColumn get reference => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
