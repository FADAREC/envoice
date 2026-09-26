import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:printing/printing.dart';

import '../../core/db/database_provider.dart';
import '../../core/db/app_database.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/utils/whatsapp.dart';
import '../../core/pdf/invoice_pdf.dart';
import '../../core/widgets/status_badge.dart';
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
  bool _busy = false;

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

  Future<List<int>> _pdfBytes() async {
    return buildInvoicePdf(
      invoice: _invoice!,
      client: _client!,
      business: _business,
      items: _items,
      payments: _payments,
    );
  }

  Future<void> _sharePdf() async {
    if (_invoice == null || _client == null || _busy) return;
    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    try {
      final bytes = await _pdfBytes();
      final text = buildInvoiceShareMessage(
        invoice: _invoice!,
        clientName: _client!.name,
        businessName: _business?.companyName,
      );
      await shareInvoicePdf(
        bytes: bytes,
        filename: '${_invoice!.number}.pdf',
        text: text,
      );
      if (_invoice!.status == 'draft') {
        await ref.read(databaseProvider).updateInvoiceStatus(_invoice!.id, 'sent');
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remind() async {
    if (_invoice == null || _client == null) return;
    HapticFeedback.selectionClick();
    try {
      final text = buildReminderMessage(
        invoice: _invoice!,
        clientName: _client!.name,
        businessName: _business?.companyName,
      );
      await shareText(text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open share: $e')),
        );
      }
    }
  }

  Future<void> _previewPdf() async {
    if (_invoice == null || _client == null) return;
    HapticFeedback.selectionClick();
    try {
      final bytes = await _pdfBytes();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: AppColors.fill,
            appBar: AppBar(
              title: const Text('Preview'),
              actions: [
                TextButton(
                  onPressed: () async {
                    final text = buildInvoiceShareMessage(
                      invoice: _invoice!,
                      clientName: _client!.name,
                      businessName: _business?.companyName,
                    );
                    await shareInvoicePdf(
                      bytes: bytes,
                      filename: '${_invoice!.number}.pdf',
                      text: text,
                    );
                  },
                  child: const Text('Share'),
                ),
              ],
            ),
            body: PdfPreview(
              build: (_) async => bytes,
              allowPrinting: true,
              allowSharing: true,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              pdfFileName: '${_invoice!.number}.pdf',
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not preview: $e')),
        );
      }
    }
  }

  Future<void> _recordPayment() async {
    final amountController = TextEditingController(
      text: ((_invoice!.total - _invoice!.amountPaid).clamp(0, double.infinity))
          .toStringAsFixed(2),
    );
    final referenceController = TextEditingController();
    String method = 'transfer';

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
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.fillSecondary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Record payment',
                      style: Theme.of(ctx).textTheme.headlineMedium),
                  const SizedBox(height: 20),
                  TextField(
                    controller: amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    autofocus: true,
                    style: Theme.of(ctx).textTheme.bodyLarge,
                    decoration: const InputDecoration(labelText: 'Amount'),
                  ),
                  const SizedBox(height: 16),
                  Text('Method', style: Theme.of(ctx).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final m in ['transfer', 'cash', 'card', 'pos'])
                        ChoiceChip(
                          label: Text(m[0].toUpperCase() + m.substring(1)),
                          selected: method == m,
                          onSelected: (_) => setModal(() => method = m),
                          selectedColor: AppColors.black,
                          labelStyle: TextStyle(
                            color: method == m ? Colors.white : AppColors.ink,
                            fontSize: 13,
                          ),
                          backgroundColor: AppColors.fill,
                          side: BorderSide.none,
                          showCheckmark: false,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: referenceController,
                    style: Theme.of(ctx).textTheme.bodyLarge,
                    decoration: const InputDecoration(
                      labelText: 'Reference (optional)',
                      hintText: 'Transfer ref / receipt no.',
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Save payment'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    if (ok != true) return;
    final amount = double.tryParse(amountController.text) ?? 0;
    if (amount <= 0) return;

    HapticFeedback.lightImpact();
    try {
      final db = ref.read(databaseProvider);
      final refText = referenceController.text.trim();
      await db.addPayment(PaymentsCompanion(
        id: Value(const Uuid().v4()),
        invoiceId: Value(_invoice!.id),
        amount: Value(amount),
        paidAt: Value(DateTime.now()),
        method: Value(method),
        reference: Value(refText.isEmpty ? null : refText),
      ));
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save payment: $e')),
        );
      }
    }
  }

  Future<void> _deletePayment(Payment p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete payment?'),
        content: Text(
          'Remove ${formatMoney(p.amount, symbol: _invoice!.currencySymbol)} recorded on ${_fmt(p.paidAt)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await ref.read(databaseProvider).deletePayment(p.id, _invoice!.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _invoice == null) {
      return const Scaffold(
        body: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.black),
          ),
        ),
      );
    }

    final inv = _invoice!;
    final remaining = inv.total - inv.amountPaid;
    final status = AppDatabase.effectiveStatus(inv);
    final company = _business?.companyName ?? 'Your business';

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: Text(inv.number),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 22),
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
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.fill,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  remaining > 0.001 ? 'AMOUNT DUE' : 'TOTAL',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  formatMoney(
                    remaining > 0.001 ? remaining : inv.total,
                    symbol: inv.currencySymbol,
                  ),
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        fontSize: 36,
                        letterSpacing: -1,
                      ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    StatusBadge(status: status),
                    if (inv.dueDate != null) ...[
                      const SizedBox(width: 12),
                      Text(
                        'Due ${_fmt(inv.dueDate!)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: status == 'overdue'
                                  ? AppColors.danger
                                  : AppColors.ink,
                            ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _sharePdf,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.ios_share, size: 18),
              label: Text(_busy ? 'Preparing…' : 'Share PDF'),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _previewPdf,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Preview'),
                ),
              ),
              if (remaining > 0.001) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _remind,
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('Remind'),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 32),
          _sectionLabel(context, 'From'),
          Text(company, style: Theme.of(context).textTheme.titleMedium),
          if (_business?.email != null)
            Text(_business!.email!, style: Theme.of(context).textTheme.bodySmall),
          if (_business?.tin != null)
            Text('TIN ${_business!.tin}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 20),
          if (_client != null) ...[
            _sectionLabel(context, 'Bill to'),
            Text(_client!.name, style: Theme.of(context).textTheme.titleMedium),
            if (_client!.email != null)
              Text(_client!.email!, style: Theme.of(context).textTheme.bodySmall),
            if (_client!.phone != null)
              Text(_client!.phone!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 28),
          _sectionLabel(context, 'Items'),
          const SizedBox(height: 4),
          for (final item in _items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.description,
                            style: Theme.of(context).textTheme.bodyLarge),
                        const SizedBox(height: 2),
                        Text(
                          '${_qty(item.quantity)} × ${formatMoney(item.unitPrice, symbol: inv.currencySymbol)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    formatMoney(item.amount, symbol: inv.currencySymbol),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          const Divider(height: 32),
          _kv(context, 'Subtotal',
              formatMoney(inv.subtotal, symbol: inv.currencySymbol)),
          if (inv.discountAmount > 0)
            _kv(context, 'Discount',
                '- ${formatMoney(inv.discountAmount, symbol: inv.currencySymbol)}'),
          if (inv.vatAmount > 0)
            _kv(context, 'VAT (${inv.vatRate}%)',
                formatMoney(inv.vatAmount, symbol: inv.currencySymbol)),
          _kv(context, 'Total',
              formatMoney(inv.total, symbol: inv.currencySymbol),
              bold: true),
          if (inv.amountPaid > 0)
            _kv(context, 'Paid',
                formatMoney(inv.amountPaid, symbol: inv.currencySymbol)),
          if (remaining > 0.001)
            _kv(context, 'Balance due',
                formatMoney(remaining, symbol: inv.currencySymbol),
                bold: true),
          if (_payments.isNotEmpty) ...[
            const SizedBox(height: 28),
            _sectionLabel(context, 'Payments'),
            for (final p in _payments)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formatMoney(p.amount, symbol: inv.currencySymbol),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            [
                              _fmt(p.paidAt),
                              if (p.method != null) p.method!,
                              if (p.reference != null) 'ref ${p.reference}',
                            ].join(' · '),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _deletePayment(p),
                      icon: const Icon(Icons.delete_outline, size: 20),
                      color: AppColors.secondary,
                      tooltip: 'Delete payment',
                    ),
                  ],
                ),
              ),
          ],
          if (inv.notes != null && inv.notes!.isNotEmpty) ...[
            const SizedBox(height: 24),
            _sectionLabel(context, 'Notes'),
            Text(inv.notes!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
      bottomNavigationBar: remaining > 0.001
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: ElevatedButton(
                  onPressed: _recordPayment,
                  child: const Text('Record payment'),
                ),
              ),
            )
          : null,
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              letterSpacing: 1.1,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v, {bool bold = false}) {
    final style = bold
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(k, style: style), Text(v, style: style)],
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _qty(double q) {
    if (q == q.roundToDouble()) return q.toInt().toString();
    return q.toStringAsFixed(2);
  }
}
