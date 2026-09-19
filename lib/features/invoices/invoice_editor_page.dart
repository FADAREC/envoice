import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column;

import '../../core/db/database_provider.dart';
import '../../core/db/app_database.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';

class _LineItem {
  String description;
  double quantity;
  double unitPrice;

  _LineItem({
    this.description = '',
    this.quantity = 1,
    this.unitPrice = 0,
  });

  double get amount => quantity * unitPrice;
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    _clients = await db.getAllClients();
    final profile = await db.getBusinessProfile();
    if (profile != null) {
      _vatEnabled = profile.vatEnabledByDefault;
      _vatRate = profile.defaultVatRate;
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
        final items = await db.getInvoiceItems(inv.id);
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

  double get _subtotal => _items.fold(0.0, (s, i) => s + i.amount);
  double get _afterDiscount => (_subtotal - _discount).clamp(0, double.infinity);
  double get _vatAmount => _vatEnabled ? _afterDiscount * (_vatRate / 100) : 0;
  double get _total => _afterDiscount + _vatAmount;

  Future<void> _save({required String status}) async {
    if (_clientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a client')),
      );
      return;
    }
    if (_items.every((i) => i.description.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one line item')),
      );
      return;
    }

    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    final id = _existingId ?? _uuid.v4();
    final number = _existingNumber ?? await db.allocateInvoiceNumber();
    final now = DateTime.now();

    final inv = InvoicesCompanion(
      id: Value(id),
      number: Value(number),
      clientId: Value(_clientId!),
      status: Value(status),
      issueDate: Value(_issueDate),
      dueDate: Value(_dueDate),
      subtotal: Value(_subtotal),
      discountAmount: Value(_discount),
      vatRate: Value(_vatEnabled ? _vatRate : 0),
      vatAmount: Value(_vatAmount),
      total: Value(_total),
      notes: Value(_notes.text.trim().isEmpty ? null : _notes.text.trim()),
      createdAt: _existingId == null ? Value(now) : const Value.absent(),
      updatedAt: Value(now),
    );

    final itemCompanions = <InvoiceItemsCompanion>[];
    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      if (item.description.trim().isEmpty) continue;
      itemCompanions.add(InvoiceItemsCompanion(
        id: Value(_uuid.v4()),
        invoiceId: Value(id),
        description: Value(item.description.trim()),
        quantity: Value(item.quantity),
        unitPrice: Value(item.unitPrice),
        amount: Value(item.amount),
        sortOrder: Value(i),
      ));
    }

    await db.upsertInvoice(inv, itemCompanions);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _notes.dispose();
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
      appBar: AppBar(
        title: Text(_existingId == null ? 'New invoice' : 'Edit invoice'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
        children: [
          Text('Client', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _clientId,
            items: _clients
                .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                .toList(),
            onChanged: (v) => setState(() => _clientId = v),
            decoration: const InputDecoration(hintText: 'Select client'),
          ),
          if (_clients.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Add a client first from the Clients tab',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.warning,
                    ),
              ),
            ),
          const SizedBox(height: 24),
          Text('Line items', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          for (var i = 0; i < _items.length; i++) _buildItemRow(i),
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
                child: Text('Discount (₦)', style: Theme.of(context).textTheme.bodyMedium),
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
          _TotalRow(label: 'Subtotal', value: formatMoney(_subtotal)),
          if (_discount > 0)
            _TotalRow(label: 'Discount', value: '- ${formatMoney(_discount)}'),
          if (_vatEnabled)
            _TotalRow(label: 'VAT', value: formatMoney(_vatAmount)),
          _TotalRow(label: 'Total', value: formatMoney(_total), bold: true),
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
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
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

  Widget _buildItemRow(int index) {
    final item = _items[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          TextFormField(
            initialValue: item.description,
            decoration: const InputDecoration(hintText: 'Description'),
            onChanged: (v) => item.description = v,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: item.quantity == 1 ? '1' : item.quantity.toString(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Qty'),
                  onChanged: (v) => setState(() {
                    item.quantity = double.tryParse(v) ?? 1;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  initialValue:
                      item.unitPrice == 0 ? '' : item.unitPrice.toStringAsFixed(0),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Unit price'),
                  onChanged: (v) => setState(() {
                    item.unitPrice = double.tryParse(v) ?? 0;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 40,
                child: IconButton(
                  onPressed: _items.length == 1
                      ? null
                      : () => setState(() => _items.removeAt(index)),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
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
