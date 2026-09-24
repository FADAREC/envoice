import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column;

import '../../core/db/database_provider.dart';
import '../../core/db/app_database.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state.dart';

final clientsProvider = FutureProvider<List<Client>>((ref) async {
  return ref.watch(databaseProvider).getAllClients();
});

class ClientsPage extends ConsumerStatefulWidget {
  const ClientsPage({super.key});

  @override
  ConsumerState<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends ConsumerState<ClientsPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clientsAsync = ref.watch(clientsProvider);

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
                      'Clients',
                      style: Theme.of(context).textTheme.displayLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => _openEditor(context),
                    icon: const Icon(Icons.add_circle, size: 28),
                    color: AppColors.black,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v.trim()),
                style: Theme.of(context).textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: 'Search',
                  prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.tertiary),
                  filled: true,
                  fillColor: AppColors.fill,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.black, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: clientsAsync.when(
                loading: () => const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.black),
                  ),
                ),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (clients) {
                  final filtered = _query.isEmpty
                      ? clients
                      : clients.where((c) {
                          final q = _query.toLowerCase();
                          return c.name.toLowerCase().contains(q) ||
                              (c.email?.toLowerCase().contains(q) ?? false) ||
                              (c.company?.toLowerCase().contains(q) ?? false) ||
                              (c.phone?.contains(q) ?? false);
                        }).toList();

                  if (filtered.isEmpty) {
                    return EmptyState(
                      icon: Icons.people_outline_rounded,
                      title: _query.isEmpty ? 'No clients yet' : 'No matches',
                      message: _query.isEmpty
                          ? 'Add the people and companies you bill. You will pick them when creating invoices.'
                          : 'Try a different name, email, or phone.',
                      actionLabel: _query.isEmpty ? 'Add client' : null,
                      onAction: _query.isEmpty ? () => _openEditor(context) : null,
                    );
                  }

                  return ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final c = filtered[i];
                      final subtitle = [c.company, c.email, c.phone]
                          .where((e) => e != null && e.isNotEmpty)
                          .join(' · ');

                      return Material(
                        color: AppColors.white,
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            _openEditor(context, client: c);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 22,
                                  backgroundColor: AppColors.fill,
                                  child: Text(
                                    c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.ink,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        c.name,
                                        style: Theme.of(context).textTheme.titleMedium,
                                      ),
                                      if (subtitle.isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Text(
                                          subtitle,
                                          style: Theme.of(context).textTheme.bodySmall,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                  color: AppColors.tertiary,
                                ),
                              ],
                            ),
                          ),
                        ),
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

  Future<void> _openEditor(BuildContext context, {Client? client}) async {
    HapticFeedback.mediumImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ClientEditorPage(client: client)),
    );
    ref.invalidate(clientsProvider);
  }
}

class ClientEditorPage extends ConsumerStatefulWidget {
  final Client? client;

  const ClientEditorPage({super.key, this.client});

  @override
  ConsumerState<ClientEditorPage> createState() => _ClientEditorPageState();
}

class _ClientEditorPageState extends ConsumerState<ClientEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _company;
  late final TextEditingController _address;
  late final TextEditingController _notes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.client;
    _name = TextEditingController(text: c?.name ?? '');
    _email = TextEditingController(text: c?.email ?? '');
    _phone = TextEditingController(text: c?.phone ?? '');
    _company = TextEditingController(text: c?.company ?? '');
    _address = TextEditingController(text: c?.addressLine1 ?? '');
    _notes = TextEditingController(text: c?.notes ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _company.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.lightImpact();
    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    final id = widget.client?.id ?? const Uuid().v4();
    final now = DateTime.now();

    await db.upsertClient(ClientsCompanion(
      id: Value(id),
      name: Value(_name.text.trim()),
      email: Value(_email.text.trim().isEmpty ? null : _email.text.trim()),
      phone: Value(_phone.text.trim().isEmpty ? null : _phone.text.trim()),
      company: Value(_company.text.trim().isEmpty ? null : _company.text.trim()),
      addressLine1: Value(_address.text.trim().isEmpty ? null : _address.text.trim()),
      notes: Value(_notes.text.trim().isEmpty ? null : _notes.text.trim()),
      createdAt: widget.client == null ? Value(now) : const Value.absent(),
      updatedAt: Value(now),
    ));

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.client == null;

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: Text(isNew ? 'New client' : 'Edit client'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    'Save',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.systemBlue,
                    ),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            _Field(
              controller: _name,
              label: 'Name',
              autofocus: isNew,
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _company,
              label: 'Company',
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _email,
              label: 'Email',
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _phone,
              label: 'Phone',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _address,
              label: 'Address',
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _notes,
              label: 'Notes',
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int maxLines;
  final bool autofocus;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
    this.autofocus = false,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      maxLines: maxLines,
      autofocus: autofocus,
      validator: validator,
      style: Theme.of(context).textTheme.bodyLarge,
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }
}
