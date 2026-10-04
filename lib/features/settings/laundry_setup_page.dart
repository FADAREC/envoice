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
                  '$n item${n == 1 ? '' : 's'} at ₦0. Set prices or the drop-off picker stays empty.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              );
            },
          ),
          Text('Branch tag prefix',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Used on new tags only (e.g. M-00041). Existing tags do not change.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          const _BranchPrefixTile(),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: Text('Services',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              TextButton(
                onPressed: () => _addService(context, ref),
                child: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const _ServicesSection(),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: Text('Price catalog',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              TextButton(
                onPressed: () => _addCatalogRow(context, ref),
                child: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const _CatalogSection(),
        ],
      ),
    );
  }

  Future<void> _addService(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New service'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'e.g. Express, Iron only',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final name = controller.text.trim();
    if (name.isEmpty) return;
    try {
      await ref.read(databaseProvider).upsertService(name: name);
      ref.invalidate(servicesProvider);
      ref.invalidate(catalogProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    }
  }

  Future<void> _addCatalogRow(BuildContext context, WidgetRef ref) async {
    final services = await ref.read(databaseProvider).getActiveServices();
    if (services.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add a service first')),
        );
      }
      return;
    }
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController(text: '0');
    var serviceId = services.first.id;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return AlertDialog(
              title: const Text('Catalog item'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Item name'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: serviceId,
                    decoration: const InputDecoration(labelText: 'Service'),
                    items: [
                      for (final s in services)
                        DropdownMenuItem(value: s.id, child: Text(s.name)),
                    ],
                    onChanged: (v) {
                      if (v != null) setModal(() => serviceId = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Price (₦)'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Save')),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    final price = double.tryParse(priceCtrl.text.trim()) ?? 0;
    if (name.isEmpty) return;
    try {
      await ref.read(databaseProvider).upsertCatalogItem(
            name: name,
            serviceId: serviceId,
            unitPrice: price,
          );
      ref.invalidate(catalogProvider);
      ref.invalidate(zeroPriceCountProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    }
  }
}

class _BranchPrefixTile extends ConsumerWidget {
  const _BranchPrefixTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(businessProfileProvider);
    return profileAsync.when(
      loading: () => const LinearProgressIndicator(minHeight: 2),
      error: (e, _) => Text('$e'),
      data: (profile) {
        final current = (profile?.branchPrefix ?? 'M').toUpperCase();
        return Row(
          children: [
            _PrefixChip(
              label: 'M · Mainland',
              selected: current == 'M',
              onTap: () => _setPrefix(context, ref, profile, 'M'),
            ),
            const SizedBox(width: 10),
            _PrefixChip(
              label: 'I · Island',
              selected: current == 'I',
              onTap: () => _setPrefix(context, ref, profile, 'I'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _setPrefix(
    BuildContext context,
    WidgetRef ref,
    BusinessProfile? profile,
    String prefix,
  ) async {
    final current = (profile?.branchPrefix ?? 'M').toUpperCase();
    if (current == prefix) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change branch prefix?'),
        content: Text(
          'Only new tags will use $prefix. Existing tags (like $current-00041) stay the same. Customers still need the number printed on their ticket.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Change')),
        ],
      ),
    );
    if (ok != true) return;

    final db = ref.read(databaseProvider);
    await db.upsertBusinessProfile(
      BusinessProfilesCompanion(
        companyName: Value(profile?.companyName ?? 'My Laundry'),
        branchPrefix: Value(prefix),
      ),
    );
    ref.invalidate(businessProfileProvider);
  }
}

class _PrefixChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PrefixChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.black : AppColors.fill,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.white : AppColors.ink,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _ServicesSection extends ConsumerWidget {
  const _ServicesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(servicesProvider);
    return async.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (e, _) => Text('$e'),
      data: (all) {
        final active = all.where((s) => s.active).toList();
        final archived = all.where((s) => !s.active).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in active) _ServiceTile(service: s, archived: false),
            if (archived.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Archived', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              for (final s in archived)
                _ServiceTile(service: s, archived: true),
            ],
          ],
        );
      },
    );
  }
}

class _ServiceTile extends ConsumerWidget {
  final Service service;
  final bool archived;

  const _ServiceTile({required this.service, required this.archived});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(service.name),
      subtitle: archived ? const Text('Archived') : null,
      trailing: archived
          ? TextButton(
              onPressed: () async {
                await ref
                    .read(databaseProvider)
                    .setServiceActive(service.id, true);
                ref.invalidate(servicesProvider);
              },
              child: const Text('Restore'),
            )
          : IconButton(
              icon: const Icon(Icons.archive_outlined, size: 20),
              onPressed: () => _archive(context, ref),
            ),
      onTap: archived
          ? null
          : () async {
              final ctrl = TextEditingController(text: service.name);
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Rename service'),
                  content: TextField(controller: ctrl, autofocus: true),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Save')),
                  ],
                ),
              );
              if (ok != true) return;
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              await ref.read(databaseProvider).upsertService(
                    name: name,
                    id: service.id,
                    sortOrder: service.sortOrder,
                    active: service.active,
                  );
              ref.invalidate(servicesProvider);
            },
    );
  }

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    final linked = await ref
        .read(databaseProvider)
        .countActiveCatalogForService(service.id);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive service?'),
        content: Text(
          linked > 0
              ? 'This service still has $linked active catalog item${linked == 1 ? '' : 's'}. They will stay in the catalog but this service will hide from new drop-offs. You can restore it later.'
              : 'Staff will not see this service on new drop-offs. You can restore it from Archived.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Archive')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(databaseProvider).setServiceActive(service.id, false);
    ref.invalidate(servicesProvider);
  }
}

class _CatalogSection extends ConsumerWidget {
  const _CatalogSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(catalogProvider);
    final servicesAsync = ref.watch(servicesProvider);

    return catalogAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (e, _) => Text('$e'),
      data: (items) {
        final services = servicesAsync.valueOrNull ?? [];
        final serviceName = {for (final s in services) s.id: s.name};
        final active = items.where((i) => i.active).toList();
        final archived = items.where((i) => !i.active).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in active)
              _CatalogTile(
                item: item,
                serviceLabel: serviceName[item.serviceId] ?? 'Service',
                archived: false,
              ),
            if (archived.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Archived items',
                  style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              for (final item in archived)
                _CatalogTile(
                  item: item,
                  serviceLabel: serviceName[item.serviceId] ?? 'Service',
                  archived: true,
                ),
            ],
          ],
        );
      },
    );
  }
}

class _CatalogTile extends ConsumerWidget {
  final CatalogItem item;
  final String serviceLabel;
  final bool archived;

  const _CatalogTile({
    required this.item,
    required this.serviceLabel,
    required this.archived,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final priceNeedsSet = item.unitPrice <= 0;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(item.name),
      subtitle: Text(
        priceNeedsSet
            ? '$serviceLabel · price needed'
            : '$serviceLabel · ₦${item.unitPrice.toStringAsFixed(0)}',
        style: TextStyle(
          color: priceNeedsSet ? AppColors.danger : AppColors.secondary,
        ),
      ),
      trailing: archived
          ? TextButton(
              onPressed: () async {
                await ref
                    .read(databaseProvider)
                    .setCatalogItemActive(item.id, true);
                ref.invalidate(catalogProvider);
                ref.invalidate(zeroPriceCountProvider);
              },
              child: const Text('Restore'),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _editPrice(context, ref),
                ),
                IconButton(
                  icon: const Icon(Icons.archive_outlined, size: 20),
                  onPressed: () async {
                    await ref
                        .read(databaseProvider)
                        .setCatalogItemActive(item.id, false);
                    ref.invalidate(catalogProvider);
                    ref.invalidate(zeroPriceCountProvider);
                  },
                ),
              ],
            ),
    );
  }

  Future<void> _editPrice(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(
      text: item.unitPrice > 0 ? item.unitPrice.toStringAsFixed(0) : '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.name),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Price (₦)'),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final price = double.tryParse(ctrl.text.trim()) ?? 0;
    await ref.read(databaseProvider).updateCatalogPrice(item.id, price);
    ref.invalidate(catalogProvider);
    ref.invalidate(zeroPriceCountProvider);
  }
}
