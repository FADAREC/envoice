import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../db/app_database.dart';
import '../utils/money.dart';

/// Premium client-facing invoice.
/// Hierarchy: amount due first, then due date, brand, line items, payment notes.
/// Designed to feel like a document from a top-tier service brand, not a template.
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

  // Soft near-black for print + screen
  const ink = PdfColor.fromInt(0xFF1C1C1E);
  const muted = PdfColor.fromInt(0xFF8E8E93);
  const line = PdfColor.fromInt(0xFFE5E5EA);
  const fill = PdfColor.fromInt(0xFFF7F7F8);

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(48, 48, 48, 48),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // ── Brand row ───────────────────────────────────────────
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (logo != null) ...[
                      pw.Container(
                        height: 40,
                        width: 40,
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
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            color: ink,
                          ),
                        ),
                        if (business?.email != null || business?.phone != null)
                          pw.Text(
                            [
                              if (business?.email != null) business!.email!,
                              if (business?.phone != null) business!.phone!,
                            ].join('  ·  '),
                            style: const pw.TextStyle(fontSize: 9, color: muted),
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
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 2.0,
                        color: muted,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      invoice.number,
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: ink,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            pw.SizedBox(height: 40),

            // ── Amount due hero ─────────────────────────────────────
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(vertical: 28, horizontal: 24),
              decoration: pw.BoxDecoration(
                color: fill,
                borderRadius: pw.BorderRadius.circular(12),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    showBalance ? 'AMOUNT DUE' : 'TOTAL',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 1.4,
                      color: muted,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    formatMoney(showBalance ? balance : invoice.total, symbol: symbol),
                    style: pw.TextStyle(
                      fontSize: 32,
                      fontWeight: pw.FontWeight.bold,
                      color: ink,
                      letterSpacing: -0.5,
                    ),
                  ),
                  if (invoice.dueDate != null) ...[
                    pw.SizedBox(height: 10),
                    pw.Text(
                      'Due ${_fmtLong(invoice.dueDate!)}',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: ink,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            pw.SizedBox(height: 32),

            // ── Meta: from / to / dates ──────────────────────────────
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'FROM',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 1.2,
                          color: muted,
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        companyName,
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: ink,
                        ),
                      ),
                      if (business?.addressLine1 != null)
                        pw.Text(business!.addressLine1!,
                            style: const pw.TextStyle(fontSize: 9, color: muted)),
                      if (business?.city != null || business?.state != null)
                        pw.Text(
                          [business?.city, business?.state]
                              .whereType<String>()
                              .join(', '),
                          style: const pw.TextStyle(fontSize: 9, color: muted),
                        ),
                      if (business?.tin != null)
                        pw.Text('TIN ${business!.tin}',
                            style: const pw.TextStyle(fontSize: 9, color: muted)),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'BILL TO',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 1.2,
                          color: muted,
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        client.name,
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: ink,
                        ),
                      ),
                      if (client.company != null)
                        pw.Text(client.company!,
                            style: const pw.TextStyle(fontSize: 9, color: muted)),
                      if (client.email != null)
                        pw.Text(client.email!,
                            style: const pw.TextStyle(fontSize: 9, color: muted)),
                      if (client.phone != null)
                        pw.Text(client.phone!,
                            style: const pw.TextStyle(fontSize: 9, color: muted)),
                      if (client.addressLine1 != null)
                        pw.Text(client.addressLine1!,
                            style: const pw.TextStyle(fontSize: 9, color: muted)),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'DETAILS',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 1.2,
                          color: muted,
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      _metaLine('Issued', _fmt(invoice.issueDate)),
                      if (invoice.dueDate != null)
                        _metaLine('Due', _fmt(invoice.dueDate!)),
                      _metaLine('Status', invoice.status.toUpperCase()),
                    ],
                  ),
                ),
              ],
            ),

            pw.SizedBox(height: 36),

            // ── Line items ──────────────────────────────────────────
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 8),
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: line, width: 1)),
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    flex: 5,
                    child: pw.Text('Description',
                        style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            letterSpacing: 0.8,
                            color: muted)),
                  ),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Text('Qty',
                        style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            letterSpacing: 0.8,
                            color: muted),
                        textAlign: pw.TextAlign.right),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Text('Rate',
                        style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            letterSpacing: 0.8,
                            color: muted),
                        textAlign: pw.TextAlign.right),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Text('Amount',
                        style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            letterSpacing: 0.8,
                            color: muted),
                        textAlign: pw.TextAlign.right),
                  ),
                ],
              ),
            ),

            for (final item in items)
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 12),
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

            // ── Totals ──────────────────────────────────────────────
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.SizedBox(
                width: 240,
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
                          top: pw.BorderSide(color: ink, width: 1.5),
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

            if (invoice.notes != null && invoice.notes!.isNotEmpty) ...[
              pw.SizedBox(height: 28),
              pw.Text(
                'NOTES',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1.2,
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
                  letterSpacing: 1.2,
                  color: muted,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                invoice.terms!,
                style: const pw.TextStyle(fontSize: 9, color: muted),
              ),
            ],

            pw.Spacer(),

            // ── Footer ──────────────────────────────────────────────
            pw.Container(
              padding: const pw.EdgeInsets.only(top: 16),
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
                    'Prepared with Envoice',
                    style: const pw.TextStyle(fontSize: 8, color: muted),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );

  return doc.save();
}

pw.Widget _metaLine(String k, String v) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$k  ',
            style: const pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF8E8E93)),
          ),
          pw.TextSpan(
            text: v,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: const PdfColor.fromInt(0xFF1C1C1E),
            ),
          ),
        ],
      ),
    ),
  );
}

pw.Widget _totalRow(
  String label,
  String value, {
  bool bold = false,
  bool large = false,
}) {
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
            color: const PdfColor.fromInt(0xFF1C1C1E),
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: large ? 14 : 10,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: const PdfColor.fromInt(0xFF1C1C1E),
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
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

String _qty(double q) {
  if (q == q.roundToDouble()) return q.toInt().toString();
  return q.toStringAsFixed(2);
}
