import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database_provider.dart';
import '../../core/db/app_database.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/status_badge.dart';
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

  static const _filters = ['all', 'draft', 'sent', 'partial', 'paid', 'overdue'];

  @override
  Widget build(BuildContext context) {
    final invoicesAsync = ref.watch(invoicesProvider);

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
                      'Invoices',
                      style: Theme.of(context).textTheme.displayLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => _create(context),
                    icon: const Icon(Icons.add_circle, size: 28),
                    color: AppColors.black,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _filters.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final f = _filters[i];
                  final selected = _filter == f;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _filter = f);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.black : AppColors.fill,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        f[0].toUpperCase() + f.substring(1),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: selected ? AppColors.white : AppColors.ink,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: invoicesAsync.when(
                loading: () => const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.black),
                  ),
                ),
                error: (e, _) => Center(child: Text('$e')),
                data: (invoices) {
                  final list = _applyFilter(invoices);

                  if (list.isEmpty) {
                    return EmptyState(
                      icon: Icons.description_outlined,
                      title: _filter == 'all' ? 'No invoices yet' : 'Nothing here',
                      message: _filter == 'all'
                          ? 'Create your first invoice. It takes under a minute.'
                          : 'No invoices match this filter.',
                      actionLabel: _filter == 'all' ? 'New invoice' : null,
                      onAction: _filter == 'all' ? () => _create(context) : null,
                    );
                  }

                  return ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final inv = list[i];
                      return _InvoiceRow(
                        invoice: inv,
                        onTap: () async {
                          HapticFeedback.selectionClick();
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
    );
  }

  List<Invoice> _applyFilter(List<Invoice> invoices) {
    final now = DateTime.now();
    if (_filter == 'overdue') {
      return invoices.where((i) {
        final remaining = i.total - i.amountPaid;
        return i.dueDate != null &&
            i.dueDate!.isBefore(now) &&
            remaining > 0.001 &&
            i.status != 'draft' &&
            i.status != 'paid' &&
            i.status != 'voided';
      }).toList();
    }
    if (_filter != 'all') {
      return invoices.where((i) => i.status == _filter).toList();
    }
    return invoices;
  }

  Future<void> _create(BuildContext context) async {
    HapticFeedback.mediumImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const InvoiceEditorPage()),
    );
    ref.invalidate(invoicesProvider);
  }
}

class _InvoiceRow extends StatelessWidget {
  final Invoice invoice;
  final VoidCallback onTap;

  const _InvoiceRow({required this.invoice, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final inv = invoice;
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
                      inv.number,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        StatusBadge(status: inv.status),
                        const SizedBox(width: 8),
                        Text(
                          _fmt(inv.issueDate),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                formatMoney(inv.total, symbol: inv.currencySymbol),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.tertiary),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
