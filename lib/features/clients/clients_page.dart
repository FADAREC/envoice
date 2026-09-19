import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column;

import '../../core/db/database_provider.dart';
import '../../core/db/app_database.dart';
import '../../core/theme/app_theme.dart';

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
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: Text('Clients', style: Theme.of(context).textTheme.displayLarge),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v.trim()),
                decoration: const InputDecoration(
                  hintText: 'Search clients',
                  prefixIcon: Icon(Icons.search, size: 20, color: AppColors.faint),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: clientsAsync.when(
                loading: () => const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
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
                    return Center(
                      child: Text(
                        _query.isEmpty ? 'No clients yet' : 'No matches',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.muted,
                            ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final c = filtered[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(c.name, style: Theme.of(context).textTheme.titleMedium),
                        subtitle: Text(
                          [c.company, c.email, c.phone]
                              .where((e) => e != null && e.isNotEmpty)
                              .join(' · '),
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _openEditor(context, client: c),
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
        onPressed: () => _openEditor(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, {Client? client}) async {
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.client == null ? 'New client' : 'Edit client'),
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
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _company,
              decoration: const InputDecoration(labelText: 'Company (optional)'),
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
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }
}
