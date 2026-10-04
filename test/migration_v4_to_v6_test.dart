import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:envoice/core/db/app_database.dart';

/// Builds a v4-shaped SQLite DB with catalog + order rows, opens AppDatabase
/// so upgrades run, and asserts service mapping + order line snapshots.
void main() {
  test('v4-shaped data upgrades and uniqueness holds on nameKey', () async {
    final executor = NativeDatabase.memory();

    await executor.runCustom('''
CREATE TABLE clients (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NULL,
  phone TEXT NULL,
  company TEXT NULL,
  address_line1 TEXT NULL,
  address_line2 TEXT NULL,
  city TEXT NULL,
  state TEXT NULL,
  notes TEXT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');
    await executor.runCustom('''
CREATE TABLE catalog_items (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  service_type TEXT NOT NULL,
  unit_price REAL NOT NULL DEFAULT 0.0,
  active INTEGER NOT NULL DEFAULT 1,
  sort_order INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL
);
''');
    await executor.runCustom('''
CREATE TABLE orders (
  id TEXT NOT NULL PRIMARY KEY,
  tag_number TEXT NOT NULL,
  client_id TEXT NOT NULL,
  workflow_status TEXT NOT NULL DEFAULT 'received',
  payment_status TEXT NOT NULL DEFAULT 'unpaid',
  dropoff_at INTEGER NOT NULL,
  expected_pickup INTEGER NULL,
  currency_code TEXT NOT NULL DEFAULT 'NGN',
  currency_symbol TEXT NOT NULL DEFAULT 'N',
  subtotal REAL NOT NULL DEFAULT 0.0,
  discount_amount REAL NOT NULL DEFAULT 0.0,
  total REAL NOT NULL DEFAULT 0.0,
  amount_paid REAL NOT NULL DEFAULT 0.0,
  notes TEXT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');
    await executor.runCustom('''
CREATE TABLE order_items (
  id TEXT NOT NULL PRIMARY KEY,
  order_id TEXT NOT NULL,
  catalog_item_id TEXT NULL,
  description TEXT NOT NULL,
  service_type TEXT NOT NULL,
  quantity REAL NOT NULL DEFAULT 1.0,
  unit_price REAL NOT NULL DEFAULT 0.0,
  amount REAL NOT NULL DEFAULT 0.0,
  sort_order INTEGER NOT NULL DEFAULT 0
);
''');
    await executor.runCustom('''
CREATE TABLE business_profiles (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  company_name TEXT NOT NULL,
  email TEXT NULL,
  phone TEXT NULL,
  address_line1 TEXT NULL,
  address_line2 TEXT NULL,
  city TEXT NULL,
  state TEXT NULL,
  country TEXT NOT NULL DEFAULT 'Nigeria',
  tin TEXT NULL,
  logo_path TEXT NULL,
  accent_color TEXT NOT NULL DEFAULT '#0A0A0A',
  invoice_prefix TEXT NOT NULL DEFAULT 'INV',
  next_invoice_number INTEGER NOT NULL DEFAULT 1,
  branch_prefix TEXT NOT NULL DEFAULT 'M',
  next_tag_number INTEGER NOT NULL DEFAULT 1,
  default_vat_rate REAL NOT NULL DEFAULT 7.5,
  vat_enabled_by_default INTEGER NOT NULL DEFAULT 0,
  currency_code TEXT NOT NULL DEFAULT 'NGN',
  currency_symbol TEXT NOT NULL DEFAULT 'N',
  bank_name TEXT NULL,
  bank_account_name TEXT NULL,
  bank_account_number TEXT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await executor.runInsert(
      'INSERT INTO clients (id, name, created_at, updated_at) VALUES (?, ?, ?, ?)',
      ['c1', 'Ada Obi', now, now],
    );
    await executor.runInsert(
      '''INSERT INTO catalog_items
      (id, name, service_type, unit_price, active, sort_order, updated_at)
      VALUES (?, ?, ?, ?, 1, 10, ?)''',
      ['cat1', 'Shirt / top', 'wash_fold', 800.0, now],
    );
    await executor.runInsert(
      '''INSERT INTO catalog_items
      (id, name, service_type, unit_price, active, sort_order, updated_at)
      VALUES (?, ?, ?, ?, 1, 11, ?)''',
      ['cat2', 'Shirt / top', 'dry_clean', 1500.0, now],
    );
    await executor.runInsert(
      '''INSERT INTO orders
      (id, tag_number, client_id, workflow_status, payment_status,
       dropoff_at, subtotal, total, amount_paid, created_at, updated_at)
      VALUES (?, ?, ?, 'received', 'unpaid', ?, 800, 800, 0, ?, ?)''',
      ['o1', 'M-00001', 'c1', now, now, now],
    );
    await executor.runInsert(
      '''INSERT INTO order_items
      (id, order_id, catalog_item_id, description, service_type,
       quantity, unit_price, amount, sort_order)
      VALUES (?, ?, ?, ?, ?, 1, 800, 800, 0)''',
      ['oi1', 'o1', 'cat1', 'Shirt / top', 'wash_fold'],
    );

    await executor.runCustom('PRAGMA user_version = 4;');

    final db = AppDatabase.forTesting(executor);
    await db.customSelect('SELECT 1').get();

    final services = await db.getAllServices();
    expect(services.map((s) => s.id).toSet(),
        containsAll([kServiceWashFold, kServiceDryClean]));

    final catalog = await db.getAllCatalog();
    final wash = catalog.where((c) =>
        c.name == 'Shirt / top' && c.serviceId == kServiceWashFold);
    final dry = catalog.where((c) =>
        c.name == 'Shirt / top' && c.serviceId == kServiceDryClean);
    expect(wash.length, 1);
    expect(wash.first.unitPrice, 800);
    expect(dry.length, 1);
    expect(dry.first.unitPrice, 1500);

    final items = await db.getOrderItems('o1');
    expect(items.length, 1);
    expect(items.first.description, 'Shirt / top');
    expect(items.first.serviceName, 'Wash & Fold');
    expect(items.first.unitPrice, 800);

    await db.upsertCatalogItem(
      name: '  SHIRT / top ',
      serviceId: kServiceWashFold,
      unitPrice: 900,
    );
    final again = await db.getAllCatalog();
    final washAgain = again.where((c) =>
        c.nameKey == 'shirt / top' && c.serviceId == kServiceWashFold);
    expect(washAgain.length, 1);
    expect(washAgain.first.unitPrice, 900);

    await db.close();
  });
}
