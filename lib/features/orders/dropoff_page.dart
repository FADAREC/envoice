import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/db/database_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../clients/clients_page.dart';
import '../settings/laundry_setup_page.dart';
import 'orders_page.dart';

final pricedCatalogProvider = FutureProvider<List<CatalogItem>>((ref) {
  return ref.watch(databaseProvider).getPricedActiveCatalog();
});

class DropoffPage extends ConsumerStatefulWidget {
  const DropoffPage({super.key});

  @override
  ConsumerState<DropoffPage> createState() => _DropoffPageState();
}

class _CartLine {
  final CatalogItem item;
  final String serviceName;
  int qty;
  _CartLine({required this.item, required this.serviceName, this.qty = 1});
  double get amount => item.unitPrice * qty;
}

class _DropoffPageState extends ConsumerState<DropoffPage> {
  Client? _client;
  final Map<String, _CartLine> _cart = {};
  DateTime? _expectedPickup;
  bool _saving = false;
  String? _error;

  double get _total => _cart.values.fold<double>(0, (s, l) => s + l.amount);
  int get _itemCount => _cart.values.fold<int>(0, (s, l) => s + l.qty);

  void _addItem(CatalogItem item, String serviceName) {
    HapticFeedback.selectionClick();
    setState(() {
      final existing = _cart[item.id];
      if (existing != null) {
        existing.qty += 1;
      } else {
        _cart[item.id] = _CartLine(item: item, serviceName: serviceName);
      }
      _error = null;
    });
  }

  void _decItem(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      final line = _cart[id];
      if (line == null) return;
      if (line.qty <= 1) {
        _cart.remove(id);
      } else {
        line.qty -= 1;
      }
    });
  }

  Future<void> _pickClient() async {
    final clients = await ref.read(databaseProvider).getAllClients();
    if (!mounted) return;
    final chosen = await showModalBottomSheet<Client>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        var query = '';
        return StatefulBuilder(builder: (ctx, setModal) {
          final filtered = query.isEmpty
              ? clients
              : clients
                  .where((c) {
                    final q = query.toLowerCase();
                    return c.name.toLowerCase().contains(q) ||
                        (c.phone?.contains(q) ?? false);
                  })
                  .toList();
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            minChildSize: 0.45,
            maxChildSize: 0.92,
            builder: (ctx, scroll) {
              return Column(children: [
                const SizedBox(height: 12),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.fillSecondary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(children: [
                    Expanded(
                      child: Text('Customer',
                          style: Theme.of(ctx).textTheme.headlineMedium),
                    ),
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ClientEditorPage(),
                          ),
                        );
                        ref.invalidate(clientsProvider);
                        if (mounted) _pickClient();
                      },
                      child: const Text('New'),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    autofocus: true,
                    onChanged: (v) => setModal(() => query = v.trim()),
                    decoration: const InputDecoration(
                      hintText: 'Search name or phone',
                      prefixIcon: Icon(Icons.search, size: 20),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            clients.isEmpty
                                ? 'No customers yet. Tap New.'
                                : 'No matches',
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        )
                      : ListView.builder(
                          controller: scroll,
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final c = filtered[i];
                            return ListTile(
                              title: Text(c.name),
                              subtitle:
                                  c.phone != null ? Text(c.phone!) : null,
                              onTap: () => Navigator.pop(ctx, c),
                            );
                          },
                        ),
                ),
              ]);
            },
          );
        });
      },
    );
    if (chosen != null && mounted) {
      setState(() {
        _client = chosen;
        _error = null;
      });
    }
  }

  Future<void> _pickPickupDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expectedPickup ?? now.add(const Duration(days: 2)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
    );
    if (picked != null && mounted) setState(() => _expectedPickup = picked);
  }

  Future<void> _confirm() async {
    if (_client == null) {
      setState(() => _error = 'Pick a customer first');
      return;
    }
    if (_cart.isEmpty) {
      setState(() => _error = 'Add at least one item');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final db = ref.read(databaseProvider);
      final profile = await db.getBusinessProfile();
      final symbol = profile?.currencySymbol ?? '\u20a6';
      final code = profile?.currencyCode ?? 'NGN';
      final orderId = const Uuid().v4();
      final now = DateTime.now();
      final total = _total;
      final items = <OrderItemsCompanion>[];
      var sort = 0;
      for (final line in _cart.values) {
        items.add(OrderItemsCompanion.insert(
          id: const Uuid().v4(),
          orderId: orderId,
          catalogItemId: Value(line.item.id),
          description: line.item.name,
          serviceName: line.serviceName,
          quantity: Value(line.qty.toDouble()),
          unitPrice: Value(line.item.unitPrice),
          amount: Value(line.amount),
          sortOrder: Value(sort++),
        ));
      }
      final tag = await db.createOrderWithTag(
        orderWithoutTag: OrdersCompanion.insert(
          id: orderId,
          tagNumber: 'TEMP',
          clientId: _client!.id,
          dropoffAt: now,
          expectedPickup: Value(_expectedPickup),
          currencyCode: Value(code),
          currencySymbol: Value(symbol),
          subtotal: Value(total),
          total: Value(total),
          amountPaid: const Value(0),
          workflowStatus: const Value('received'),
          paymentStatus: const Value('unpaid'),
        ),
        items: items,
      );
      if (!mounted) return;
      ref.invalidate(ordersProvider);
      ref.invalidate(clientsProvider);
      final lineTuples = _cart.values
          .map((l) => (
                l.item.name + ' · ' + l.serviceName,
                l.qty,
                l.amount,
              ))
          .toList();
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DropoffSuccessPage(
            tagNumber: tag,
            total: total,
            currencySymbol: symbol,
            client: _client!,
            expectedPickup: _expectedPickup,
            lines: lineTuples,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save order: ' + e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(pricedCatalogProvider);
    final servicesAsync = ref.watch(servicesProvider);
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('Drop-off'),
        actions: [
          TextButton(
            onPressed: _pickPickupDate,
            child: Text(
              _expectedPickup == null
                  ? 'Pickup date'
                  : 'Pickup ' +
                      _expectedPickup!.day.toString() +
                      '/' +
                      _expectedPickup!.month.toString(),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Material(
            color: AppColors.fill,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: _pickClient,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(children: [
                  Icon(
                    _client == null
                        ? Icons.person_add_alt_1_outlined
                        : Icons.person_rounded,
                    size: 22,
                    color: AppColors.ink,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _client?.name ?? 'Select customer',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (_client?.phone != null) ...[
                          const SizedBox(height: 2),
                          Text(_client!.phone!,
                              style: Theme.of(context).textTheme.bodySmall),
                        ] else if (_client == null) ...[
                          const SizedBox(height: 2),
                          Text('Required',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.secondary)),
                        ],
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      size: 20, color: AppColors.tertiary),
                ]),
              ),
            ),
          ),
        ),
        Expanded(
          child: catalogAsync.when(
            loading: () => const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.black),
              ),
            ),
            error: (e, _) => Center(child: Text(e.toString())),
            data: (items) {
              if (items.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('No priced items yet',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(
                        'Set prices in Settings, Services and prices. Items at zero stay hidden here on purpose.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 20),
                      OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const LaundrySetupPage(),
                            ),
                          );
                        },
                        child: const Text('Open laundry setup'),
                      ),
                    ],
                  ),
                );
              }
              final services = servicesAsync.valueOrNull ?? [];
              final serviceName = {for (final s in services) s.id: s.name};
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final item = items[i];
                  final svc = serviceName[item.serviceId] ?? 'Service';
                  final inCart = _cart[item.id];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color:
                          inCart != null ? AppColors.fill : AppColors.white,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: () => _addItem(item, svc),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: inCart != null
                                  ? AppColors.black
                                  : AppColors.hairline,
                              width: inCart != null ? 1.5 : 0.5,
                            ),
                          ),
                          child: Row(children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const SizedBox(height: 2),
                                  Text(
                                    svc + ' · ' + formatMoney(item.unitPrice),
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            if (inCart != null) ...[
                              IconButton(
                                onPressed: () => _decItem(item.id),
                                icon: const Icon(Icons.remove_circle_outline,
                                    size: 22),
                                color: AppColors.ink,
                              ),
                              Text(inCart.qty.toString(),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium),
                              IconButton(
                                onPressed: () => _addItem(item, svc),
                                icon: const Icon(Icons.add_circle_outline,
                                    size: 22),
                                color: AppColors.ink,
                              ),
                            ] else
                              const Icon(Icons.add,
                                  size: 22, color: AppColors.tertiary),
                          ]),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              _error!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.danger),
            ),
          ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            decoration: const BoxDecoration(
              color: AppColors.white,
              border: Border(
                top: BorderSide(color: AppColors.hairline, width: 0.5),
              ),
            ),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _itemCount.toString() + ' items',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      formatMoney(_total),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 160,
                child: ElevatedButton(
                  onPressed: _saving ? null : _confirm,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.white,
                          ),
                        )
                      : const Text('Confirm'),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class DropoffSuccessPage extends StatelessWidget {
  final String tagNumber;
  final double total;
  final String currencySymbol;
  final Client client;
  final DateTime? expectedPickup;
  final List<(String label, int qty, double amount)> lines;

  const DropoffSuccessPage({
    super.key,
    required this.tagNumber,
    required this.total,
    required this.currencySymbol,
    required this.client,
    required this.expectedPickup,
    required this.lines,
  });

  String _message() {
    final buf = StringBuffer();
    buf.writeln('Tag: ' + tagNumber);
    buf.writeln('Customer: ' + client.name);
    if (client.phone != null) buf.writeln('Phone: ' + client.phone!);
    buf.writeln('');
    for (final line in lines) {
      buf.writeln(line.$2.toString() +
          ' x ' +
          line.$1 +
          ' - ' +
          currencySymbol +
          line.$3.toStringAsFixed(0));
    }
    buf.writeln('');
    buf.writeln('Total: ' +
        currencySymbol +
        total.toStringAsFixed(0) +
        ' (unpaid)');
    if (expectedPickup != null) {
      final d = expectedPickup!;
      buf.writeln('Expected pickup: ' +
          d.day.toString().padLeft(2, '0') +
          '/' +
          d.month.toString().padLeft(2, '0') +
          '/' +
          d.year.toString());
    }
    buf.writeln('');
    buf.writeln('Keep this tag number for collection.');
    return buf.toString();
  }

  Future<void> _share() async {
    try {
      await Share.share(_message(), subject: 'Tag ' + tagNumber);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Order saved', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Text(
                tagNumber,
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontSize: 44,
                      letterSpacing: -1.2,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(client.name,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                formatMoney(total, symbol: currencySymbol),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 28),
              Expanded(
                child: ListView(
                  children: [
                    for (final line in lines)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          Text(line.$2.toString(),
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(line.$1,
                                  style:
                                      Theme.of(context).textTheme.bodyMedium)),
                          Text(
                            formatMoney(line.$3, symbol: currencySymbol),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ]),
                      ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: _share,
                child: const Text('Share on WhatsApp'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
