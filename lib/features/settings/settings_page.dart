import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;

import '../../core/db/database_provider.dart';
import '../../core/db/app_database.dart';
import '../../core/theme/app_theme.dart';
import '../../core/security/app_lock.dart';
import '../../core/backup/backup_service.dart';
import 'logo_pick.dart';
import '../dashboard/dashboard_page.dart';
import '../invoices/invoices_page.dart';
import '../clients/clients_page.dart';

final businessProfileProvider = FutureProvider<BusinessProfile?>((ref) async {
  return ref.watch(databaseProvider).getBusinessProfile();
});

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _lock = AppLock();
  bool _lockEnabled = false;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadLockState();
  }

  Future<void> _loadLockState() async {
    final enabled = await _lock.isLockEnabled();
    final bio = await _lock.isBiometricEnabled();
    final canBio = await _lock.canCheckBiometrics();
    if (!mounted) return;
    setState(() {
      _lockEnabled = enabled;
      _biometricEnabled = bio;
      _biometricAvailable = canBio;
    });
  }

  Future<void> _setupLock() async {
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    var useBio = _biometricAvailable;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
          ),
          child: StatefulBuilder(
            builder: (ctx, setModal) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Set app lock', style: Theme.of(ctx).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Anyone who opens this phone will need the PIN before they can see your invoices.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: pinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    decoration: const InputDecoration(
                      labelText: 'PIN (4-8 digits)',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    decoration: const InputDecoration(
                      labelText: 'Confirm PIN',
                      counterText: '',
                    ),
                  ),
                  if (_biometricAvailable)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Allow fingerprint / face'),
                      value: useBio,
                      activeColor: AppColors.black,
                      onChanged: (v) => setModal(() => useBio = v),
                    ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      if (pinController.text.length < 4) return;
                      if (pinController.text != confirmController.text) return;
                      Navigator.pop(ctx, true);
                    },
                    child: const Text('Turn on lock'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    if (ok != true) return;
    if (pinController.text.length < 4 ||
        pinController.text != confirmController.text) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PINs must match and be at least 4 digits')),
        );
      }
      return;
    }

    try {
      await _lock.enableLock(pinController.text, biometric: useBio);
      await _loadLockState();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('App lock is on')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not enable lock: $e')),
        );
      }
    }
  }

  Future<void> _disableLock() async {
    final pinController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn off lock?'),
        content: TextField(
          controller: pinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Enter current PIN'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Turn off'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _lock.disableLock(pinController.text.trim());
      await _loadLockState();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('App lock is off')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Future<void> _exportBackup() async {
    setState(() => _busy = true);
    try {
      final service = BackupService(ref.read(databaseProvider));
      await service.exportAndShare();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not export: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importBackup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore backup?'),
        content: const Text(
          'This replaces all invoices, clients, and business details on this phone with the backup file. Export first if you are not sure.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Restore',
              style: TextStyle(
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      final service = BackupService(ref.read(databaseProvider));
      final count = await service.importFromPicker();
      ref.invalidate(businessProfileProvider);
      ref.invalidate(dashboardStatsProvider);
      ref.invalidate(invoicesProvider);
      ref.invalidate(clientsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restored $count invoices')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not restore: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(businessProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
          children: [
            Text('Settings', style: Theme.of(context).textTheme.displayLarge),
            const SizedBox(height: 8),
            Text(
              'Business brand, security, and backup.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 28),
            profileAsync.when(
              loading: () => const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.black),
                ),
              ),
              error: (e, _) => Text('$e'),
              data: (profile) => _ProfileCard(
                profile: profile,
                onEdit: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          BusinessProfileEditorPage(profile: profile),
                    ),
                  );
                  ref.invalidate(businessProfileProvider);
                },
              ),
            ),
            const SizedBox(height: 28),
            Text('Security', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Stops anyone with your unlocked phone from opening Envoice and sending invoices as your business.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('App lock (PIN)'),
              subtitle: Text(_lockEnabled ? 'On' : 'Off'),
              value: _lockEnabled,
              activeColor: AppColors.black,
              onChanged: (v) async {
                HapticFeedback.selectionClick();
                if (v) {
                  await _setupLock();
                } else {
                  await _disableLock();
                }
              },
            ),
            if (_lockEnabled && _biometricAvailable)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fingerprint / face unlock'),
                value: _biometricEnabled,
                activeColor: AppColors.black,
                onChanged: (v) async {
                  await _lock.setBiometric(v);
                  await _loadLockState();
                },
              ),
            const SizedBox(height: 28),
            Text('Backup', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Clearing app data or losing this phone wipes local history. Export a backup to Drive, Files, or WhatsApp to yourself regularly.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _busy ? null : _exportBackup,
              icon: const Icon(Icons.upload_outlined, size: 18),
              label: const Text('Export backup'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _importBackup,
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('Restore from backup'),
            ),
            const SizedBox(height: 32),
            Text(
              'Envoice',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.tertiary,
                  ),
            ),
            Text(
              'Offline-first. Data lives on this device until you export.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final BusinessProfile? profile;
  final VoidCallback onEdit;

  const _ProfileCard({required this.profile, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.hairline),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (profile?.logoPath != null &&
                  File(profile!.logoPath!).existsSync())
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(profile!.logoPath!),
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    key: ValueKey(profile!.logoPath),
                  ),
                )
              else
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.fill,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.business, color: AppColors.tertiary),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile?.companyName ?? 'Set up your business',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (profile?.email != null)
                      Text(profile!.email!,
                          style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onEdit,
              child: Text(
                  profile == null ? 'Add business details' : 'Edit business profile'),
            ),
          ),
        ],
      ),
    );
  }
}

class BusinessProfileEditorPage extends ConsumerStatefulWidget {
  final BusinessProfile? profile;

  const BusinessProfileEditorPage({super.key, this.profile});

  @override
  ConsumerState<BusinessProfileEditorPage> createState() =>
      _BusinessProfileEditorPageState();
}

class _BusinessProfileEditorPageState
    extends ConsumerState<BusinessProfileEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _city;
  late final TextEditingController _state;
  late final TextEditingController _tin;
  late final TextEditingController _bankName;
  late final TextEditingController _bankAccountName;
  late final TextEditingController _bankAccountNumber;
  late final TextEditingController _prefix;
  late final TextEditingController _currencySymbol;
  String? _logoPath;
  String _accentColor = '#0A0A0A';
  bool _vatDefault = false;
  bool _saving = false;

  static const _accentChoices = [
    ('#0A0A0A', 'Black'),
    ('#1C1C1E', 'Ink'),
    ('#8B1A1A', 'Deep red'),
    ('#1A3A5C', 'Navy'),
    ('#0D5C4C', 'Forest'),
    ('#5C4A1A', 'Gold'),
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _name = TextEditingController(text: p?.companyName ?? '');
    _email = TextEditingController(text: p?.email ?? '');
    _phone = TextEditingController(text: p?.phone ?? '');
    _address = TextEditingController(text: p?.addressLine1 ?? '');
    _city = TextEditingController(text: p?.city ?? '');
    _state = TextEditingController(text: p?.state ?? '');
    _tin = TextEditingController(text: p?.tin ?? '');
    _bankName = TextEditingController(text: p?.bankName ?? '');
    _bankAccountName = TextEditingController(text: p?.bankAccountName ?? '');
    _bankAccountNumber = TextEditingController(text: p?.bankAccountNumber ?? '');
    _prefix = TextEditingController(text: p?.invoicePrefix ?? 'INV');
    _currencySymbol = TextEditingController(text: p?.currencySymbol ?? '₦');
    _logoPath = p?.logoPath;
    _accentColor = p?.accentColor ?? '#0A0A0A';
    _vatDefault = p?.vatEnabledByDefault ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _address.dispose();
    _city.dispose();
    _state.dispose();
    _tin.dispose();
    _bankName.dispose();
    _bankAccountName.dispose();
    _bankAccountNumber.dispose();
    _prefix.dispose();
    _currencySymbol.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final path = await pickAndStoreLogo(previousPath: _logoPath);
    if (path != null) setState(() => _logoPath = path);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      await db.upsertBusinessProfile(BusinessProfilesCompanion(
        companyName: Value(_name.text.trim()),
        email: Value(_email.text.trim().isEmpty ? null : _email.text.trim()),
        phone: Value(_phone.text.trim().isEmpty ? null : _phone.text.trim()),
        addressLine1:
            Value(_address.text.trim().isEmpty ? null : _address.text.trim()),
        city: Value(_city.text.trim().isEmpty ? null : _city.text.trim()),
        state: Value(_state.text.trim().isEmpty ? null : _state.text.trim()),
        tin: Value(_tin.text.trim().isEmpty ? null : _tin.text.trim()),
        bankName: Value(_bankName.text.trim().isEmpty ? null : _bankName.text.trim()),
        bankAccountName: Value(_bankAccountName.text.trim().isEmpty ? null : _bankAccountName.text.trim()),
        bankAccountNumber: Value(_bankAccountNumber.text.trim().isEmpty ? null : _bankAccountNumber.text.trim()),
        logoPath: Value(_logoPath),
        accentColor: Value(_accentColor),
        invoicePrefix:
            Value(_prefix.text.trim().isEmpty ? 'INV' : _prefix.text.trim()),
        currencySymbol: Value(
          _currencySymbol.text.trim().isEmpty ? '₦' : _currencySymbol.text.trim(),
        ),
        vatEnabledByDefault: Value(_vatDefault),
        updatedAt: Value(DateTime.now()),
      ));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('Business profile'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.black),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickLogo,
                child: Column(
                  children: [
                    if (_logoPath != null && File(_logoPath!).existsSync())
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(_logoPath!),
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          key: ValueKey(_logoPath),
                        ),
                      )
                    else
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppColors.fill,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.add_a_photo_outlined,
                            color: AppColors.secondary),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      _logoPath == null ? 'Add logo' : 'Change logo',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.systemBlue,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Business name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(labelText: 'Phone'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _city,
                    decoration: const InputDecoration(labelText: 'City'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _state,
                    decoration: const InputDecoration(labelText: 'State'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _tin,
              decoration: const InputDecoration(labelText: 'TIN (optional)'),
            ),
            const SizedBox(height: 20),
            Text('Payment details (on invoice)',
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 10),
            TextFormField(
              controller: _bankName,
              decoration: const InputDecoration(
                labelText: 'Bank name',
                hintText: 'e.g. GTBank',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bankAccountName,
              decoration: const InputDecoration(
                labelText: 'Account name',
                hintText: 'Name on the account',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bankAccountNumber,
              decoration: const InputDecoration(
                labelText: 'Account number',
                hintText: '10-digit NUBAN',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _prefix,
              decoration: const InputDecoration(
                labelText: 'Invoice number prefix',
                hintText: 'INV',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _currencySymbol,
              decoration: const InputDecoration(
                labelText: 'Currency symbol',
                hintText: '₦',
              ),
            ),
            const SizedBox(height: 20),
            Text('Brand accent (on PDF)',
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (hex, label) in _accentChoices)
                  GestureDetector(
                    onTap: () => setState(() => _accentColor = hex),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Color(
                          int.parse(hex.replaceFirst('#', '0xFF')),
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _accentColor == hex
                              ? AppColors.black
                              : AppColors.hairline,
                          width: _accentColor == hex ? 2.5 : 1,
                        ),
                      ),
                      child: _accentColor == hex
                          ? const Icon(Icons.check, color: Colors.white, size: 18)
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('VAT on by default (7.5%)'),
              value: _vatDefault,
              activeColor: AppColors.black,
              onChanged: (v) => setState(() => _vatDefault = v),
            ),
          ],
        ),
      ),
    );
  }
}
