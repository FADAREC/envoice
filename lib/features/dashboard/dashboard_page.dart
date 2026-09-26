import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database_provider.dart';
import '../../core/db/app_database.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../invoices/invoice_editor_page.dart';
import '../invoices/invoice_detail_page.dart';
import '../invoices/invoices_page.dart';
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
              SpiverToBoxAdapter_PLACEHOLDER
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
    // Keep every tab's list in sync — IndexedStack caches FutureProviders.
    ref.invalidate(dashboardStatsProvider);
    ref.invalidate(invoicesProvider);
  }
}
