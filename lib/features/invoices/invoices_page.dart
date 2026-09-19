import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database_provider.dart';
import '../../core/db/app_database.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import 'invoice_editor_page.dart';
import 'invoice_detail_page.dart';

final invoicesProvider = FutureProvider<List<Invoice>>((ref) async {
  return ref.watch(databaseProvider).getAllInvoices();
});

class InvoicesPage extends ConsumerStatefulWidget {
  const InvoicesPage({super.key});

  @override
  ConsumerState<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends ConsumerState<InvoicesPage> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final invoicesAsync = ref.watch(invoicesProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: Text('Invoices', style: Theme.of(context).textTheme.displayLarge),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  for (final f in ['all', 'draft', 'sent', 'partial', 'paid', 'overdue'])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(f[0].toUpperCase() + f.substring(1)),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                        selectedColor: AppColors.black,
                        labelStyle: TextStyle(
                          color: _filter == f ? Colors.white : AppColors.ink,
                          fontSize: 13,
                        ),
                        backgroundColor: AppColors.surface,
                        side: BorderSide.none,
                        showCheckmark: false,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: invoicesAsync.when(
                loading: () => const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.black),
                  ),
                ),
                error: (e, _) => Center(child: Text('$e')),
                data: (invoices) {
                  final now = DateTime.now();
                  var list = invoices;
                  if (_filter == 'overdue') {
                    list = invoices.where((i) {
                      final remaining = i.total - i.amountPaid;
                      return i.dueDate != null &&
                          i.dueDate!.isBefore(now) &&
                          remaining > 0.001 &&
                          i.status != 'draft' &&
                          i.status != 'paid' &&
                          i.status != 'voided';
                    }).toList();
                  } else if (_filter != 'all') {
                    list = invoices.where((i) => i.status == _filter).toList();
                  }

                  if (list.isEmpty) {
                    return Center(
                      child: Text(
                        'No invoices',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.muted,
                            ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final inv = list[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                inv.number,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Text(
                              formatMoney(inv.total, symbol: inv.currencySymbol),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              _StatusPill(status: inv.status),
                              const SizedBox(width: 8),
                              Text(
                                '${inv.issueDate.day}/${inv.issueDate.month}/${inv.issueDate.year}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => InvoiceDetailPage(invoiceId: inv.id),
                            ),
                          );
                          ref.invalidate(invoicesProvider);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const InvoiceEditorPage()),
          );
          ref.invalidate(invoicesProvider);
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;

  const _StatusPill({required this.status});

  Color get _color {
    switch (status) {
      case 'paid':
        return AppColors.success;
      case 'overdue':
      case 'voided':
        return AppColors.danger;
      case 'partial':
        return AppColors.warning;
      case 'sent':
        return AppColors.ink;
      default:
        return AppColors.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: _color,
        ),
      ),
    );
  }
}
