import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/db/database_provider.dart';
import '../../core/theme/app_theme.dart';
import 'settings_page.dart';

final servicesProvider = FutureProvider<List<Service>>((ref) {
  return ref.watch(databaseProvider).getAllServices();
});

final catalogProvider = FutureProvider<List<CatalogItem>>((ref) {
  return ref.watch(databaseProvider).getAllCatalog();
});

final zeroPriceCountProvider = FutureProvider<int>((ref) {
  return ref.watch(databaseProvider).countZeroPriceActiveCatalog();
});

/// Services, price catalog, and branch prefix for laundry Stage 1.
class LaundrySetupPage extends ConsumerWidget {
  const LaundrySetupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zeroAsync = ref.watch(zeroPriceCountProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(title: const Text('Laundry setup')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
        children: [
          zeroAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (n) {
              if (n <= 0) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.fill,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '" + str(n) + "', // will fix
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
