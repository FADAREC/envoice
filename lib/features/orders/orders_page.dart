import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/db/database_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/empty_state.dart';
import 'dropoff_page.dart';

final ordersProvider = FutureProvider<List<Order>>((ref) {
  return ref.watch(databaseProvider).getAllOrders();
});

class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({super.key});

  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(ordersProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Orders',
                      style: Theme.of(context).textTheme.displayLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () async {
                      HapticFeedback.mediumImpact();
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DropoffPage(),
                        ),
                      );
                      ref.invalidate(ordersProvider);
                    },
                    icon: const Icon(Icons.add_circle, size: 28),
                    color: AppColors.black,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  for (final f in const [
                    ('all', 'All'),
                    ('received', 'Received'),
                    ('washing', 'Washing'),
                    ('ready', 'Ready'),
                    ('collected', 'Collected'),
                    ('unpaid', 'Unpaid'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _FilterChip(
                        label: f.$2,
                        selected: _filter == f.$1,
                        onTap: () => setState(() => _filter = f.$1),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ordersAsync.when(
                loading: () => const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.black),
                  ),
                ),
                error: (e, _) => Center(child: Text(e.toString())),
                data: (orders) {
                  final filtered = orders.where((o) {
                    if (_filter == 'all') return true;
                    if (_filter == 'unpaid') {
                      return o.paymentStatus != 'paid';
                    }
                    return o.workflowStatus == _filter;
                  }).toList();

                  if (filtered.isEmpty) {
                    return EmptyState(
                      icon: Icons.local_laundry_service_outlined,
                      title: orders.isEmpty ? 'No orders yet' : 'Nothing here',
                      message: orders.isEmpty
                          ? 'Start a drop-off. Customer, items, tag number in under a minute.'
                          : 'Try another filter.',
                      actionLabel: orders.isEmpty ? 'New drop-off' : null,
                      onAction: orders.isEmpty
                          ? () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const DropoffPage(),
                                ),
                              );
                              ref.invalidate(ordersProvider);
                            }
                          : null,
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async {
                      HapticFeedback.lightImpact();
                      ref.invalidate(ordersProvider);
                    },
                    color: AppColors.black,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final o = filtered[i];
                        return _OrderTile(
                          order: o,
                          onTap: () async {
                            HapticFeedback.selectionClick();
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    OrderDetailPage(orderId: o.id),
                              ),
                            );
                            ref.invalidate(ordersProvider);
                          },
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.black : AppColors.fill,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.white : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderTile extends ConsumerWidget {
  final Order order;
  final VoidCallback onTap;

  const _OrderTile({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Client?>(
      future: ref.read(databaseProvider).getClient(order.clientId),
      builder: (context, snap) {
        final name = snap.data?.name ?? 'Customer';
        final unpaid = order.paymentStatus != 'paid';
        final subtitle = name +
            ' · ' +
            order.workflowStatus +
            (unpaid ? ' · unpaid' : '');
        return Material(
          color: AppColors.white,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.tagNumber,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: unpaid
                                    ? AppColors.warning
                                    : AppColors.secondary,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    formatMoney(order.total, symbol: order.currencySymbol),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right,
                      size: 18, color: AppColors.tertiary),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class OrderDetailPage extends ConsumerStatefulWidget {
  final String orderId;

  const OrderDetailPage({super.key, required this.orderId});

  @override
  ConsumerState<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends ConsumerState<OrderDetailPage> {
  bool _busy = false;

  Future<void> _setWorkflow(String status) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(databaseProvider)
          .updateOrderWorkflow(widget.orderId, status);
      ref.invalidate(ordersProvider);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);

    return FutureBuilder(
      future: Future.wait([
        db.getOrder(widget.orderId),
        db.getOrderItems(widget.orderId),
      ]),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.black),
            ),
          );
        }
        final order = snap.data![0] as Order?;
        final items = snap.data![1] as List<OrderItem>;
        if (order == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Order not found')),
          );
        }

        final statusLine = order.paymentStatus + ' · ' + order.workflowStatus;

        return Scaffold(
          backgroundColor: AppColors.white,
          appBar: AppBar(title: Text(order.tagNumber)),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              Text(
                formatMoney(order.total, symbol: order.currencySymbol),
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 4),
              Text(
                statusLine,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              Text('Items', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final it in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Text(
                        it.quantity.toInt().toString() + 'x',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          it.description + ' · ' + it.serviceName,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      Text(
                        formatMoney(it.amount, symbol: order.currencySymbol),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 28),
              Text('Status', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in const [
                    'received',
                    'washing',
                    'ready',
                    'collected',
                  ])
                    ChoiceChip(
                      label: Text(s),
                      selected: order.workflowStatus == s,
                      onSelected: _busy ? null : (_) => _setWorkflow(s),
                      selectedColor: AppColors.black,
                      labelStyle: TextStyle(
                        color: order.workflowStatus == s
                            ? AppColors.white
                            : AppColors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
