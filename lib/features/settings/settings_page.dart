import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:drift/drift.dart' hide Column;

import '../../core/db/database_provider.dart';
import '../../core/db/app_database.dart';
import '../../core/theme/app_theme.dart';

final businessProfileProvider = FutureProvider<BusinessProfile?>((ref) async {
  return ref.watch(databaseProvider).getBusinessProfile();
});

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(businessProfileProvider);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
          children: [
            Text('Settings', style: Theme.of(context).textTheme.displayLarge),
            const SizedBox(height: 8),
            Text(
              'Your company brand appears on every invoice.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 28),
            profileAsync.when(
              loading: () => const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.black),
                ),
              ),
              error: (e, _) => Text('$e'),
              data: (profile) => _ProfileCard(
                profile: profile,
                onEdit: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BusinessProfileEditorPage(profile: profile),
                    ),
                  );
                  ref.invalidate(businessProfileProvider);
                },
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Envoice',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.faint,
                  ),
            ),
            Text(
              'Offline-first invoicing. Data stays on this device.',
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
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (profile?.logoPath != null && File(profile!.logoPath!).existsSync())
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(profile!.logoPath!),
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  ),
                )
              else
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.business, color: AppColors.faint),
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
                      Text(profile!.email!, style: Theme.of(context).textTheme.bodySmall),
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
              child: Text(profile == null ? 'Add business details' : 'Edit business profile'),
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
  late final TextEditingController _prefix;
  String? _logoPath;
  bool _vatDefault = false;
  bool _saving = false;

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
    _prefix = TextEditingController(text: p?.invoicePrefix ?? 'INV');
    _logoPath = p?.logoPath;
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
    _prefix.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (file == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final dest = File(p.join(dir.path, 'business_logo${p.extension(file.path)}'));
    await File(file.path).copy(dest.path);
    setState(() => _logoPath = dest.path);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final db = ref.read(databaseProvider);
    await db.upsertBusinessProfile(BusinessProfilesCompanion(
      companyName: Value(_name.text.trim()),
      email: Value(_email.text.trim().isEmpty ? null : _email.text.trim()),
      phone: Value(_phone.text.trim().isEmpty ? null : _phone.text.trim()),
      addressLine1: Value(_address.text.trim().isEmpty ? null : _address.text.trim()),
      city: Value(_city.text.trim().isEmpty ? null : _city.text.trim()),
      state: Value(_state.text.trim().isEmpty ? null : _state.text.trim()),
      tin: Value(_tin.text.trim().isEmpty ? null : _tin.text.trim()),
      logoPath: Value(_logoPath),
      invoicePrefix: Value(_prefix.text.trim().isEmpty ? 'INV' : _prefix.text.trim()),
      vatEnabledByDefault: Value(_vatDefault),
      updatedAt: Value(DateTime.now()),
    ));

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Business profile'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
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
                        ),
                      )
                    else
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: const Icon(Icons.add_a_photo_outlined, color: AppColors.faint),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Company logo',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Company name'),
              textCapitalization: TextCapitalization.words,
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
            const SizedBox(height: 16),
            TextFormField(
              controller: _prefix,
              decoration: const InputDecoration(
                labelText: 'Invoice number prefix',
                hintText: 'INV',
              ),
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
