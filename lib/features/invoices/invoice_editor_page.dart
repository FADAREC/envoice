import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column;

import '../../core/db/database_provider.dart';
import '../../core/db/app_database.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../clients/clients_page.dart';

class _LineItem {
  final String key;
  final TextEditingController description;
  final TextEditingController quantity;
  final TextEditingController unitPrice;

  _LineItem({
    String? id,
    String description = '',
    double quantity = 1,
    double unitPrice = 0,
  })  : key = id ?? const Uuid().v4(),
        description = TextEditingController(text: description),
        quantity = TextEditingController(
          text: quantity == 1 ? '1' : quantity.toString(),
        ),
        unitPrice = TextEditingController(
          text: unitPrice == 0 ? '' : unitPrice.toStringAsFixed(0),
        );

  double get quantityValue => double.tryParse(quantity.text) ?? 1;
  double get unitPriceValue => double.tryParse(unitPrice.text) ?? 0;
  double get amount => quantityValue * unitPriceValue;

  void dispose() {
    description.dispose();
    quantity.dispose();
    unitPrice.dispose();
  }
}

class InvoiceEditorPage extends ConsumerStatefulWidget {
  final String? invoiceId;

  const InvoiceEditorPage({super.key, this.invoiceId});

  @override
  ConsumerState<InvoiceEditorPage> createState() => _InvoiceEditorPageState();
}

class _InvoiceEditorPageState extends ConsumerState<InvoiceEditorPage> {
  final _uuid = const Uuid();
  List<Client> _clients = [];
  String? _clientId;
  final _items = <_LineItem>[_LineItem()];
  double _discount = 0;
  bool _vatEnabled = false;
  double _vatRate = 7.5;
  DateTime _issueDate = DateTime.now();
  DateTime? _dueDate;
  final _notes = TextEditingController();
  bool _saving = false;
  bool _loading = true;
  String? _existingId;
  String? _existingNumber;
  String? _currencySymbol;

  @override
  void initState() {
    super.initState();
    _dueDate = DateTime.now().add(const Duration(days: 7));
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    _clients = await db.getAllClients();
    final profile = await db.getBusinessProfile();
    if (profile != null) {
      _vatEnabled = profile.vatEnabledByDefault;
      _vatRate = profile.defaultVatRate;
      _currencySymbol = profile.currencySymbol;
    }

    if (widget.invoiceId != null) {
      final inv = await db.getInvoice(widget.invoiceId!);
      if (inv != null) {
        _existingId = inv.id;
        _existingNumber = inv.number;
        _clientId = inv.clientId;
        _discount = inv.discountAmount;
        _vatEnabled = inv.vatRate > 0;
        _vatRate = inv.vatRate > 0 ? inv.vatRate : _vatRate;
        _issueDate = inv.issueDate;
        _dueDate = inv.dueDate;
        _notes.text = inv.notes ?? '';
        _currencySymbol = inv.currencySymbol;
        final items = await db.getInvoiceItems(inv.id);
        for (final i in _items) {
          i.dispose();
        }
        _items
          ..clear()
          ..addAll(items.map((i) => _LineItem(
                description: i.description,
                quantity: i.quantity,
                unitPrice: i.unitPrice,
              )));
        if (_items.isEmpty) _items.add(_LineItem());
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addClientInline() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ClientEditorPage()),
    );
    final db = ref.read(databaseProvider);
    final list = await db.getAllClients();
    if (!mounted) return;
    setState(() {
      _clients = list;
      if (_clientId == null && list.isNotEmpty) {
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        _clientId = list.first.id;
      }
    });
  }

  double get _subtotal => _items.fold(0.0, (s, i) => s + i.amount);
  double get _afterDiscount => (_subtotal - _discount).clamp(0, double.infinity);
  double get _vatAmount => _vatEnabled ? _afterDiscount * (_vatRate / 100) : 0;
  double get _total => _afterDiscount + _vatAmount;
  String get _sym => _currencySymbol ?? '₦';

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _save({required String status}) async {
    if (_clientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a client')),
      );
      return;
    }
    if (_items.every((i) => i.description.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one line item')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      final id = _existingId ?? _uuid.v4();
      final now = DateTime.now();

      final itemCompanions = <InvoiceItemsCompanion>[];
      for (var i = 0; i < _items.length; i++) {
        final item = _items[i];
        if (item.description.text.trim().isEmpty) continue;
        itemCompanions.add(InvoiceItemsCompanion(
          id: Value(_uuid.v4()),
          invoiceId: Value(id),
          description: Value(item.description.text.trim()),
          quantity: Value(item.quantityValue),
          unitPrice: Value(item.unitPriceValue),
          amount: Value(item.amount),
          sortOrder: Value(i),
        ));
      }

      if (_existingId == null) {
        // New invoice: number allocation + insert are atomic
        await db.createInvoiceWithNumber(
          invoiceWithoutNumber: InvoicesCompanion(
            id: Value(id),
            number: const Value(''), // filled inside transaction
            clientId: Value(_clientId!),
            status: Value(status),
            issueDate: Value(_issueDate),
            dueDate: Value(_dueDate),
            currencySymbol: Value(_sym),
            subtotal: Value(_subtotal),
            discountAmount: Value(_discount),
            vatRate: Value(_vatEnabled ? _vatRate : 0),
            vatAmount: Value(_vatAmount),
            total: Value(_total),
            notes: Value(_notes.text.trim().isEmpty ? null : _notes.text.trim()),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
          items: itemCompanions,
        );
      } else {
        await db.upsertInvoice(
          InvoicesCompanion(
            id: Value(id),
            number: Value(_existingNumber!),
            clientId: Value(_clientId!),
            status: Value(status),
            issueDate: Value(_issueDate),
            dueDate: Value(_dueDate),
            currencySymbol: Value(_sym),
            subtotal: Value(_subtotal),
            discountAmount: Value(_discount),
            vatRate: Value(_vatEnabled ? _vatRate : 0),
            vatAmount: Value(_vatAmount),
            total: Value(_total),
            notes: Value(_notes.text.trim().isEmpty ? null : _notes.text.trim()),
            updatedAt: Value(now),
          ),
          itemCompanions,
        );
      }

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
  void dispose() {
    _notes.dispose();
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.black),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: Text(_existingId == null ? 'New invoice' : 'Edit invoice'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        children: [
          Text('Client', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          if (_clients.isEmpty)
            OutlinedButton.icon(
              onPressed: _addClientInline,
              icon: const Icon(Icons.person_add_alt_1, size: 18),
              label: const Text('Add first client'),
            )
          else ...[
            DropdownButtonFormField<String>(
              value: _clientId,
              items: _clients
                  .map((c) => DropdownMenuItem(
                        value: c.id,
                        child: Text(
                          c.company != null && c.company!.isNotEmpty
                              ? '${c.name} · ${c.company}'
                              : c.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _clientId = v),
              decoration: const InputDecoration(hintText: 'Select client'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _addClientInline,
                child: const Text('New client'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text('Due date', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Material(
            color: AppColors.fill,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: _pickDueDate,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _dueDate == null ? 'No due date' : _fmt(_dueDate!),
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                    const Icon(Icons.calendar_today_outlined,
                        size: 18, color: AppColors.secondary),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Line items', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          for (final item in _items) _buildItemRow(item),
          TextButton.icon(
            onPressed: () => setState(() => _items.add(_LineItem())),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add line'),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text('Discount ($_sym)',
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
              SizedBox(
                width: 120,
                child: TextFormField(
                  initialValue: _discount == 0 ? '' : _discount.toStringAsFixed(0),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(isDense: true),
                  onChanged: (v) => setState(() {
                    _discount = double.tryParse(v) ?? 0;
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('VAT ($_vatRate%)'),
            value: _vatEnabled,
            activeColor: AppColors.black,
            onChanged: (v) => setState(() => _vatEnabled = v),
          ),
          const SizedBox(height: 8),
          _TotalRow(label: 'Subtotal', value: formatMoney(_subtotal, symbol: _sym)),
          if (_discount > 0)
            _TotalRow(
                label: 'Discount',
                value: '- ${formatMoney(_discount, symbol: _sym)}'),
          if (_vatEnabled)
            _TotalRow(label: 'VAT', value: formatMoney(_vatAmount, symbol: _sym)),
          _TotalRow(
              label: 'Total',
              value: formatMoney(_total, symbol: _sym),
              bold: true),
          const SizedBox(height: 24),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => _save(status: 'draft'),
                  child: const Text('Save draft'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saving ? null : () => _save(status: 'sent'),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemRow(_LineItem item) {
    return Padding(
      key: ValueKey(item.key),
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          TextField(
            controller: item.description,
            decoration: const InputDecoration(hintText: 'Description'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: item.quantity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Qty'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: item.unitPrice,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Unit price'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 40,
                child: IconButton(
                  onPressed: _items.length == 1
                      ? null
                      : () => setState(() {
                            item.dispose();
                            _items.remove(item);
                          }),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _TotalRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}
