import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../db/app_database.dart';
import '../utils/money.dart';

PdfColor _parseAccent(String? hex) {
  if (hex == null || hex.isEmpty) return PdfColor.fromInt(0xFF111111);
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 6) h = 'FF$h';
  final value = int.tryParse(h, radix: 16);
  if (value == null) return PdfColor.fromInt(0xFF111111);
  return PdfColor.fromInt(value);
}

/// Client-facing status (never internal jargon like SENT).
String clientFacingStatus(Invoice invoice) {
  final status = AppDatabase.effectiveStatus(invoice);
  final balance = invoice.total - invoice.amountPaid;
  final paid = balance <= 0.001;

  if (status == 'voided') return 'Voided';
  if (status == 'draft') return 'Draft';
  if (paid || status == 'paid') return 'Paid';

  if (status == 'partial') {
    if (invoice.dueDate != null) {
      final days = invoice.dueDate!.difference(DateTime.now()).inDays;
      if (days < 0) {
        return 'Partially paid · ${-days} day${-days == 1 ? '' : 's'} overdue';
      }
      if (days == 0) return 'Partially paid · due today';
      return 'Partially paid · due in $days day${days == 1 ? '' : 's'}';
    }
    return 'Partially paid';
  }

  if (status == 'overdue' && invoice.dueDate != null) {
    final days = DateTime.now().difference(invoice.dueDate!).inDays;
    return 'Unpaid · $days day${days == 1 ? '' : 's'} overdue';
  }

  if (invoice.dueDate != null) {
    final days = invoice.dueDate!.difference(DateTime.now()).inDays;
    if (days < 0) {
      return 'Unpaid · ${-days} day${-days == 1 ? '' : 's'} overdue';
    }
    if (days == 0) return 'Unpaid · due today';
    return 'Unpaid · due in $days day${days == 1 ? '' : 's'}';
  }
  return 'Unpaid';
}

/// Unified date: 6 Oct 2026 (avoids day/month confusion).
String fmtDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

/// Client-facing invoice PDF.
/// Bundled Noto Sans so naira and Nigerian diacritics render (Helvetica has neither).
Future<Uint8List> buildInvoicePdf({
  required Invoice invoice,
  required Client client,
  required BusinessProfile? business,
  required List<InvoiceItem> items,
  required List<Payment> payments,
}) async {
  final regularData =
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
  final boldData = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
  final regular = pw.Font.ttf(regularData);
  final bold = pw.Font.ttf(boldData);

  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );

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
  final fullyPaid = balance <= 0.001;
  final hasPartial = invoice.amountPaid > 0.001 && !fullyPaid;
  final accent = _parseAccent(business?.accentColor);

  const ink = PdfColor.fromInt(0xFF111111);
  const muted = PdfColor.fromInt(0xFF4A4A4A);
  const line = PdfColor.fromInt(0xFFE8E8E8);

  final hasBank = (business?.bankName != null &&
          business!.bankName!.trim().isNotEmpty) ||
      (business?.bankAccountNumber != null &&
          business!.bankAccountNumber!.trim().isNotEmpty);

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
                            if (business?.phone != null) business!.phone!,
                            if (business?.email != null) business!.email!,
                          ].join('  ·  '),
                          style: const pw.TextStyle(fontSize: 10, color: muted),
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

        pw.SizedBox(height: 16),
        pw.Container(height: 2.5, color: accent),
        pw.SizedBox(height: 28),

        pw.Text(
          fullyPaid ? 'Total' : 'Amount due',
          style: const pw.TextStyle(fontSize: 10, color: muted),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          formatMoney(fullyPaid ? invoice.total : balance, symbol: symbol),
          style: pw.TextStyle(
            fontSize: 28,
            fontWeight: pw.FontWeight.bold,
            color: accent,
            letterSpacing: -0.4,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          clientFacingStatus(invoice),
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: ink,
          ),
        ),

        pw.SizedBox(height: 28),
        pw.Container(height: 0.5, color: line),
        pw.SizedBox(height: 24),

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
                  if (business?.phone != null) business!.phone!,
                  if (business?.email != null) business!.email!,
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
                  if (client.phone != null) client.phone!,
                  if (client.email != null) client.email!,
                  if (client.addressLine1 != null) client.addressLine1!,
                ],
              ),
            ),
            pw.Expanded(
              child: _partyBlock(
                label: 'Details',
                name: null,
                lines: [
                  'Issued ${fmtDate(invoice.issueDate)}',
                  if (invoice.dueDate != null)
                    'Due ${fmtDate(invoice.dueDate!)}',
                ],
              ),
            ),
          ],
        ),

        pw.SizedBox(height: 32),

        pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: ink, width: 1)),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(flex: 5, child: _colHead('Description')),
              pw.Expanded(
                  flex: 1, child: _colHead('Qty', align: pw.TextAlign.right)),
              pw.Expanded(
                  flex: 2, child: _colHead('Rate', align: pw.TextAlign.right)),
              pw.Expanded(
                  flex: 2,
                  child: _colHead('Amount', align: pw.TextAlign.right)),
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

        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(
            width: 220,
            child: pw.Column(
              children: [
                _totalRow(
                    'Subtotal', formatMoney(invoice.subtotal, symbol: symbol)),
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
                if (hasPartial)
                  _totalRow(
                    'Balance due',
                    formatMoney(balance, symbol: symbol),
                    bold: true,
                    accent: accent,
                  ),
              ],
            ),
          ),
        ),

        if (hasBank && !fullyPaid) ...[
          pw.SizedBox(height: 28),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: line, width: 1),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'PAYMENT INSTRUCTIONS',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1.1,
                    color: muted,
                  ),
                ),
                pw.SizedBox(height: 8),
                if (business?.bankName != null &&
                    business!.bankName!.trim().isNotEmpty)
                  pw.Text(
                    business.bankName!,
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: ink,
                    ),
                  ),
                if (business?.bankAccountName != null &&
                    business!.bankAccountName!.trim().isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 3),
                    child: pw.Text(
                      business.bankAccountName!,
                      style: const pw.TextStyle(fontSize: 10, color: ink),
                    ),
                  ),
                if (business?.bankAccountNumber != null &&
                    business!.bankAccountNumber!.trim().isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 3),
                    child: pw.Text(
                      business.bankAccountNumber!,
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: accent,
                      ),
                    ),
                  ),
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 6),
                  child: pw.Text(
                    'Use invoice ${invoice.number} as your transfer reference.',
                    style: const pw.TextStyle(fontSize: 9, color: muted),
                  ),
                ),
              ],
            ),
          ),
        ],

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
                '${fmtDate(p.paidAt)}  ·  ${formatMoney(p.amount, symbol: symbol)}'
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
  const muted = PdfColor.fromInt(0xFF4A4A4A);
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
            style: const pw.TextStyle(fontSize: 10, color: muted),
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
      color: const PdfColor.fromInt(0xFF4A4A4A),
    ),
    textAlign: align,
  );
}

pw.Widget _totalRow(
  String label,
  String value, {
  bool bold = false,
  bool large = false,
  PdfColor? accent,
}) {
  const ink = PdfColor.fromInt(0xFF111111);
  final color = accent ?? ink;
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
            color: color,
          ),
        ),
      ],
    ),
  );
}

String _qty(double q) {
  if (q == q.roundToDouble()) return q.toInt().toString();
  return q.toStringAsFixed(2);
}
