import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database_provider.dart';
import '../../core/db/app_database.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../invoices/invoice_editor_page.dart';

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
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(dashboardStatsProvider),
          color: AppColors.black,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Envoice',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              letterSpacing: 0.12 * 14,
                              color: AppColors.faint,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Overview',
                        style: Theme.of(context).textTheme.displayLarge,
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: statsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.black,
                        ),
                      ),
                    ),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Could not load stats', style: TextStyle(color: AppColors.danger)),
                  ),
                  data: (stats) => _StatsBody(stats: stats),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const InvoiceEditorPage()),
          );
          ref.invalidate(dashboardStatsProvider);
        },
        icon: const Icon(Icons.add, size: 20),
        label: const Text('New invoice'),
      ),
    );
  }
}

class _StatsBody extends StatelessWidget {
  final DashboardStats stats;

  const _StatsBody({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 100),
      child: Column(
        children: [
          _PrimaryStat(
            label: 'Outstanding',
            value: formatMoney(stats.outstanding),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SecondaryStat(
                  label: 'Paid this month',
                  value: formatMoney(stats.paidThisMonth),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SecondaryStat(
                  label: 'Overdue',
                  value: '${stats.overdueCount}',
                  emphasize: stats.overdueCount > 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _CountTile(
                  label: 'Invoices',
                  value: '${stats.invoiceCount}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _CountTile(
                  label: 'Clients',
                  value: '${stats.clientCount}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrimaryStat extends StatelessWidget {
  final String label;
  final String value;

  const _PrimaryStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.black,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.5),
                ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  color: Colors.white,
                  fontSize: 28,
                ),
          ),
        ],
      ),
    );
  }
}

class _SecondaryStat extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;

  const _SecondaryStat({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: emphasize ? AppColors.danger : AppColors.ink,
                ),
          ),
        ],
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  final String label;
  final String value;

  const _CountTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
