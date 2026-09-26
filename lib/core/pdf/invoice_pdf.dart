import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../db/app_database.dart';
import '../utils/money.dart';

/// Client-facing invoice PDF.
/// Goal: look like a document a high-end service brand would send,
/// not a generic template. Hierarchy is amount → parties → lines → totals.
Future<Uint8List> buildInvoicePdf({
  required Invoice invoice,
  required Client client,
  required BusinessProfile? business,
  required List<InvoiceItem> items,
  required List<Payment> payments,
}) async {
  final doc = pw.Document();

  pw.ImageProvider? logo;
  if (business?.logoPath != null) {
    final file = File(business!.logoPath!);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty) logo = pw.MemoryImage(bytes);
    }
  }

  final companyName = business?.companyName ?? 'Your Business';
  final symbol = invoice.currencySymbol;
  final balance = invoice.total - invoice.amountPaid;
  final showBalance = balance > 0.001;
  final status = AppDatabase.effectiveStatus(invoice);

  const ink = PdfColor.fromInt(0xFF111111);
  const muted = PdfColor.fromInt(0xFF6B6B6B);
  const line = PdfColor.fromInt(0xFFE8E8E8);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(44, 44, 44, 44),
      footer: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 12),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: line, width: 0.5)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              companyName,
              style: const pw.TextStyle(fontSize: 8, color: muted),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: muted),
            ),
          ],
        ),
      ),
      build: (context) => [
        // Brand + invoice label
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logo != null) ...[
                  pw.Container(
                    height: 36,
                    width: 36,
                    child: pw.Image(logo, fit: pw.BoxFit.contain),
                  ),
                  pw.SizedBox(width: 12),
                ],
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      companyName,
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: ink,
                      ),
                    ),
                    if (business?.email != null || business?.phone != null)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 3),
                        child: pw.Text(
                          [
                            if (business?.email != null) business!.email!,
                            if (business?.phone != null) business!.phone!,
                          ].join('  ·  '),
                          style: const pw.TextStyle(fontSize: 9, color: muted),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'INVOICE',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1.6,
                    color: muted,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  invoice.number,
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: ink,
                  ),
                ),
              ],
            ),
          ],
        ),

        pw.SizedBox(height: 36),

        // Amount due — clean, no grey box
        pw.Text(
          showBalance ? 'Amount due' : 'Total',
          style: const pw.TextStyle(fontSize: 10, color: muted),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          formatMoney(showBalance ? balance : invoice.total, symbol: symbol),
          style: pw.TextStyle(
            fontSize: 28,
            fontWeight: pw.FontWeight.bold,
            color: ink,
            letterSpacing: -0.4,
          ),
        ),
        if (invoice.dueDate != null) ...[
          pw.SizedBox(height: 6),
          pw.Text(
            'Due ${_fmtLong(invoice.dueDate!)}',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: ink,
            ),
          ),
        ],

        pw.SizedBox(height: 28),
        pw.Container(height: 0.5, color: line),
        pw.SizedBox(height: 24),

        // From / Bill to / Details
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _partyBlock(
                label: 'From',
                name: companyName,
                lines: [
                  if (business?.addressLine1 != null) business!.addressLine1!,
                  if (business?.city != null || business?.state != null)
                    [business?.city, business?.state]
                        .whereType<String>()
                        .join(', '),
                  if (business?.tin != null) 'TIN ${business!.tin}',
                ],
              ),
            ),
            pw.Expanded(
              child: _partyBlock(
                label: 'Bill to',
                name: client.name,
                lines: [
                  if (client.company != null) client.company!,
                  if (client.email != null) client.email!,
                  if (client.phone != null) client.phone!,
                  if (client.addressLine1 != null) client.addressLine1!,
                ],
              ),
            ),
            pw.Expanded(
              child: _partyBlock(
                label: 'Details',
                name: null,
                lines: [
                  'Issued ${_fmt(invoice.issueDate)}',
                  if (invoice.dueDate != null) 'Due ${_fmt(invoice.dueDate!)}',
                  'Status ${status[0].toUpperCase()}${status.substring(1)}',
                ],
              ),
            ),
          ],
        ),

        pw.SizedBox(height: 32),

        // Line items header
        pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: ink, width: 1)),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(
                flex: 5,
                child: _colHead('Description'),
              ),
              pw.Expanded(
                flex: 1,
                child: _colHead('Qty', align: pw.TextAlign.right),
              ),
              pw.Expanded(
                flex: 2,
                child: _colHead('Rate', align: pw.TextAlign.right),
              ),
              pw.Expanded(
                flex: 2,
                child: _colHead('Amount', align: pw.TextAlign.right),
              ),
            ],
          ),
        ),

        for (final item in items)
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 11),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: line, width: 0.5)),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 5,
                  child: pw.Text(
                    item.description,
                    style: const pw.TextStyle(fontSize: 10, color: ink),
                  ),
                ),
                pw.Expanded(
                  flex: 1,
                  child: pw.Text(
                    _qty(item.quantity),
                    style: const pw.TextStyle(fontSize: 10, color: ink),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
                pw.Expanded(
                  flex: 2,
                  child: pw.Text(
                    formatMoney(item.unitPrice, symbol: symbol),
                    style: const pw.TextStyle(fontSize: 10, color: ink),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
                pw.Expanded(
                  flex: 2,
                  child: pw.Text(
                    formatMoney(item.amount, symbol: symbol),
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: ink,
                    ),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
              ],
            ),
          ),

        pw.SizedBox(height: 20),

        // Totals
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(
            width: 220,
            child: pw.Column(
              children: [
                _totalRow('Subtotal', formatMoney(invoice.subtotal, symbol: symbol)),
                if (invoice.discountAmount > 0)
                  _totalRow(
                    'Discount',
                    '- ${formatMoney(invoice.discountAmount, symbol: symbol)}',
                  ),
                if (invoice.vatAmount > 0)
                  _totalRow(
                    'VAT (${invoice.vatRate}%)',
                    formatMoney(invoice.vatAmount, symbol: symbol),
                  ),
                pw.SizedBox(height: 6),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 10),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      top: pw.BorderSide(color: ink, width: 1.2),
                    ),
                  ),
                  child: _totalRow(
                    'Total',
                    formatMoney(invoice.total, symbol: symbol),
                    bold: true,
                    large: true,
                  ),
                ),
                if (invoice.amountPaid > 0)
                  _totalRow(
                    'Paid',
                    formatMoney(invoice.amountPaid, symbol: symbol),
                  ),
                if (showBalance)
                  _totalRow(
                    'Balance due',
                    formatMoney(balance, symbol: symbol),
                    bold: true,
                  ),
              ],
            ),
          ),
        ),

        if (payments.isNotEmpty) ...[
          pw.SizedBox(height: 28),
          pw.Text(
            'PAYMENTS RECEIVED',
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 1.1,
              color: muted,
            ),
          ),
          pw.SizedBox(height: 8),
          for (final p in payments)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text(
                '${_fmt(p.paidAt)}  ·  ${formatMoney(p.amount, symbol: symbol)}'
                '${p.method != null ? '  ·  ${p.method}' : ''}'
                '${p.reference != null ? '  ·  ref ${p.reference}' : ''}',
                style: const pw.TextStyle(fontSize: 9, color: muted),
              ),
            ),
        ],

        if (invoice.notes != null && invoice.notes!.isNotEmpty) ...[
          pw.SizedBox(height: 28),
          pw.Text(
            'NOTES',
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 1.1,
              color: muted,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            invoice.notes!,
            style: const pw.TextStyle(fontSize: 10, color: ink, lineSpacing: 2),
          ),
        ],

        if (invoice.terms != null && invoice.terms!.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          pw.Text(
            'TERMS',
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 1.1,
              color: muted,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            invoice.terms!,
            style: const pw.TextStyle(fontSize: 9, color: muted),
          ),
        ],
      ],
    ),
  );

  return doc.save();
}

pw.Widget _partyBlock({
  required String label,
  required String? name,
  required List<String> lines,
}) {
  const ink = PdfColor.fromInt(0xFF111111);
  const muted = PdfColor.fromInt(0xFF6B6B6B);
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        label.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 1.1,
          color: muted,
        ),
      ),
      pw.SizedBox(height: 6),
      if (name != null)
        pw.Text(
          name,
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: ink,
          ),
        ),
      for (final line in lines.where((l) => l.trim().isNotEmpty))
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2),
          child: pw.Text(
            line,
            style: const pw.TextStyle(fontSize: 9, color: muted),
          ),
        ),
    ],
  );
}

pw.Widget _colHead(String text, {pw.TextAlign align = pw.TextAlign.left}) {
  return pw.Text(
    text.toUpperCase(),
    style: pw.TextStyle(
      fontSize: 8,
      fontWeight: pw.FontWeight.bold,
      letterSpacing: 0.6,
      color: const PdfColor.fromInt(0xFF6B6B6B),
    ),
    textAlign: align,
  );
}

pw.Widget _totalRow(
  String label,
  String value, {
  bool bold = false,
  bool large = false,
}) {
  const ink = PdfColor.fromInt(0xFF111111);
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: large ? 12 : 10,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: ink,
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: large ? 12 : 10,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: ink,
          ),
        ),
      ],
    ),
  );
}

String _fmt(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _fmtLong(DateTime d) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

String _qty(double q) {
  if (q == q.roundToDouble()) return q.toInt().toString();
  return q.toStringAsFixed(2);
}
