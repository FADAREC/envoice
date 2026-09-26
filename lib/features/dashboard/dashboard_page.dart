import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database_provider.dart';
import '../../core/db/app_database.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../invoices/invoice_editor_page.dart';
import '../invoices/invoice_detail_page.dart';
import '../clients/clients_page.dart';

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  final db = ref.watch(databaseProvider);
  return db.getDashboardStats();
});

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dashboardStatsProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            HapticFeedback.lightImpact();
            ref.invalidate(dashboardStatsProvider);
          },
          color: AppColors.black,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ENVOICE',
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                    letterSpacing: 1.2,
                                    color: AppColors.tertiary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Home',
                              style: Theme.of(context).textTheme.displayLarge,
                            ),
                          ],
                        ),
                      ),
                      _CircleButton(
                        icon: Icons.add,
                        onTap: () => _newInvoice(context, ref),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
              SliverToBoxAdapter(
                child: statsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 80),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.black,
                        ),
                      ),
                    ),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Could not load overview',
                      style: TextStyle(color: AppColors.danger),
                    ),
                  ),
                  data: (stats) => _Body(
                    stats: stats,
                    onNewInvoice: () => _newInvoice(context, ref),
                    onOpenInvoice: (id) async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => InvoiceDetailPage(invoiceId: id),
                        ),
                      );
                      ref.invalidate(dashboardStatsProvider);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _newInvoice(BuildContext context, WidgetRef ref) async {
    HapticFeedback.mediumImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const InvoiceEditorPage()),
    );
    ref.invalidate(dashboardStatsProvider);
  }
}

class _Body extends StatelessWidget {
  final DashboardStats stats;
  final VoidCallback onNewInvoice;
  final Future<void> Function(String invoiceId) onOpenInvoice;

  const _Body({
    required this.stats,
    required this.onNewInvoice,
    required this.onOpenInvoice,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = stats.invoiceCount == 0 && stats.clientCount == 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Outstanding',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.secondary,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            formatMoney(stats.outstanding),
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  fontSize: 40,
                  letterSpacing: -1.0,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: 'Paid this month',
                  value: formatMoney(stats.paidThisMonth),
                ),
              ),
              Container(width: 0.5, height: 44, color: AppColors.hairline),
              Expanded(
                child: _Metric(
                  label: 'Overdue',
                  value: '${stats.overdueCount}',
                  valueColor: stats.overdueCount > 0 ? AppColors.danger : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Divider(height: 0.5),
          const SizedBox(height: 28),

          // Money owed list (must-have)
          if (stats.debtors.isNotEmpty) ...[
            Text(
              'Money owed',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Oldest first',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final d in stats.debtors.take(8))
              _DebtorRow(
                entry: d,
                onTap: () => onOpenInvoice(d.invoice.id),
              ),
            if (stats.debtors.length > 8)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '+ ${stats.debtors.length - 8} more',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 28),
            const Divider(height: 0.5),
            const SizedBox(height: 28),
          ],

          Text(
            'Quick actions',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 14),
          _ActionRow(
            icon: Icons.add_circle_outline,
            title: 'New invoice',
            subtitle: 'Create and share in under a minute',
            onTap: onNewInvoice,
          ),
          const SizedBox(height: 10),
          _ActionRow(
            icon: Icons.person_add_alt_1_outlined,
            title: 'Add client',
            subtitle: 'Save details for faster billing',
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ClientEditorPage()),
              );
            },
          ),

          if (isEmpty) ...[
            const SizedBox(height: 40),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.fill,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Start here',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add a client, then create your first invoice. Everything stays on this device until you choose to share.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.secondary,
                          height: 1.45,
                        ),
                  ),
                ],
              ),
            ),
          ] else if (stats.debtors.isEmpty) ...[
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: _CountCard(
                    label: 'Invoices',
                    value: '${stats.invoiceCount}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _CountCard(
                    label: 'Clients',
                    value: '${stats.clientCount}',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DebtorRow extends StatelessWidget {
  final OutstandingEntry entry;
  final VoidCallback onTap;

  const _DebtorRow({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final inv = entry.invoice;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.clientName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${inv.number}'
                      '${inv.dueDate != null ? ' · due ${_fmt(inv.dueDate!)}' : ''}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: entry.isOverdue
                                ? AppColors.danger
                                : AppColors.secondary,
                          ),
                    ),
                  ],
                ),
              ),
              Text(
                formatMoney(entry.remaining, symbol: inv.currencySymbol),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: entry.isOverdue ? AppColors.danger : AppColors.ink,
                    ),
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
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _Metric({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: valueColor ?? AppColors.ink,
                ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.fill,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: AppColors.ink),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: AppColors.tertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  final String label;
  final String value;

  const _CountCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.hairline, width: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(value, style: Theme.of(context).textTheme.headlineMedium),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.black,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 22, color: AppColors.white),
        ),
      ),
    );
  }
}
