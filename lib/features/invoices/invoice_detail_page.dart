import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:printing/printing.dart';

import '../../core/db/database_provider.dart';
import '../../core/db/app_database.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/pdf/invoice_pdf.dart';
import 'invoice_editor_page.dart';

class InvoiceDetailPage extends ConsumerStatefulWidget {
  final String invoiceId;

  const InvoiceDetailPage({super.key, required this.invoiceId});

  @override
  ConsumerState<InvoiceDetailPage> createState() => _InvoiceDetailPageState();
}

class _InvoiceDetailPageState extends ConsumerState<InvoiceDetailPage> {
  Invoice? _invoice;
  Client? _client;
  BusinessProfile? _business;
  List<InvoiceItem> _items = [];
  List<Payment> _payments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final inv = await db.getInvoice(widget.invoiceId);
    if (inv == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final client = await db.getClient(inv.clientId);
    final business = await db.getBusinessProfile();
    final items = await db.getInvoiceItems(inv.id);
    final payments = await db.getPaymentsForInvoice(inv.id);

    if (mounted) {
      setState(() {
        _invoice = inv;
        _client = client;
        _business = business;
        _items = items;
        _payments = payments;
        _loading = false;
      });
    }
  }

  Future<void> _sharePdf() async {
    if (_invoice == null || _client == null) return;
    final bytes = await buildInvoicePdf(
      invoice: _invoice!,
      client: _client!,
      business: _business,
      items: _items,
      payments: _payments,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: '${_invoice!.number}.pdf',
    );
  }

  Future<void> _recordPayment() async {
    final amountController = TextEditingController(
      text: ((_invoice!.total - _invoice!.amountPaid).clamp(0, double.infinity))
          .toStringAsFixed(2),
    );
    final methodController = TextEditingController(text: 'transfer');

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Record payment', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Amount'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: methodController,
                decoration: const InputDecoration(
                  labelText: 'Method (transfer, cash, card, pos)',
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save payment'),
              ),
            ],
          ),
        );
      },
    );

    if (ok != true) return;
    final amount = double.tryParse(amountController.text) ?? 0;
    if (amount <= 0) return;

    final db = ref.read(databaseProvider);
    await db.addPayment(PaymentsCompanion(
      id: Value(const Uuid().v4()),
      invoiceId: Value(_invoice!.id),
      amount: Value(amount),
      paidAt: Value(DateTime.now()),
      method: Value(methodController.text.trim().isEmpty
          ? null
          : methodController.text.trim()),
    ));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _invoice == null) {
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

    final inv = _invoice!;
    final remaining = inv.total - inv.amountPaid;

    return Scaffold(
      appBar: AppBar(
        title: Text(inv.number),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _sharePdf,
            tooltip: 'Share PDF',
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => InvoiceEditorPage(invoiceId: inv.id),
                ),
              );
              await _load();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
        children: [
          Text(
            formatMoney(inv.total, symbol: inv.currencySymbol),
            style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 28),
          ),
          const SizedBox(height: 4),
          Text(
            inv.status.toUpperCase(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 20),
          if (_client != null) ...[
            Text('Bill to', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(_client!.name, style: Theme.of(context).textTheme.titleMedium),
            if (_client!.email != null)
              Text(_client!.email!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 24),
          Text('Items', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final item in _items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.description),
                        Text(
                          '${item.quantity} × ${formatMoney(item.unitPrice, symbol: inv.currencySymbol)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Text(formatMoney(item.amount, symbol: inv.currencySymbol)),
                ],
              ),
            ),
          const Divider(),
          _kv('Subtotal', formatMoney(inv.subtotal, symbol: inv.currencySymbol)),
          if (inv.discountAmount > 0)
            _kv('Discount', '- ${formatMoney(inv.discountAmount, symbol: inv.currencySymbol)}'),
          if (inv.vatAmount > 0)
            _kv('VAT (${inv.vatRate}%)', formatMoney(inv.vatAmount, symbol: inv.currencySymbol)),
          _kv('Total', formatMoney(inv.total, symbol: inv.currencySymbol), bold: true),
          _kv('Paid', formatMoney(inv.amountPaid, symbol: inv.currencySymbol)),
          if (remaining > 0.001)
            _kv('Remaining', formatMoney(remaining, symbol: inv.currencySymbol)),
          if (_payments.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Payments', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final p in _payments)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(formatMoney(p.amount, symbol: inv.currencySymbol)),
                subtitle: Text(
                  [
                    '${p.paidAt.day}/${p.paidAt.month}/${p.paidAt.year}',
                    if (p.method != null) p.method!,
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
          if (inv.notes != null && inv.notes!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Notes', style: Theme.of(context).textTheme.bodySmall),
            Text(inv.notes!),
          ],
        ],
      ),
      bottomNavigationBar: remaining > 0.001
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: ElevatedButton(
                  onPressed: _recordPayment,
                  child: const Text('Record payment'),
                ),
              ),
            )
          : null,
    );
  }

  Widget _kv(String k, String v, {bool bold = false}) {
    final style = bold
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(k, style: style), Text(v, style: style)],
      ),
    );
  }
}
