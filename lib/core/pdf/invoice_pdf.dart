import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../db/app_database.dart';
import '../utils/money.dart';

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
      logo = pw.MemoryImage(await file.readAsBytes());
    }
  }

  final companyName = business?.companyName ?? 'Your Business';
  final symbol = invoice.currencySymbol;

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(48),
      build: (context) => [
        // Header
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logo != null)
                  pw.Container(
                    height: 48,
                    width: 48,
                    margin: const pw.EdgeInsets.only(bottom: 12),
                    child: pw.Image(logo),
                  ),
                pw.Text(
                  companyName,
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (business?.addressLine1 != null)
                  pw.Text(business!.addressLine1!, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                if (business?.city != null || business?.state != null)
                  pw.Text(
                    [business?.city, business?.state].whereType<String>().join(', '),
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                  ),
                if (business?.email != null)
                  pw.Text(business!.email!, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                if (business?.phone != null)
                  pw.Text(business!.phone!, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                if (business?.tin != null)
                  pw.Text('TIN: ${business!.tin}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'INVOICE',
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(invoice.number, style: const pw.TextStyle(fontSize: 12)),
                pw.Text(
                  'Issued ${_fmt(invoice.issueDate)}',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                ),
                if (invoice.dueDate != null)
                  pw.Text(
                    'Due ${_fmt(invoice.dueDate!)}',
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                  ),
              ],
            ),
          ],
        ),

        pw.SizedBox(height: 36),

        // Bill to
        pw.Text('BILL TO', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600, letterSpacing: 0.8)),
        pw.SizedBox(height: 6),
        pw.Text(client.name, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        if (client.company != null) pw.Text(client.company!, style: const pw.TextStyle(fontSize: 10)),
        if (client.email != null) pw.Text(client.email!, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        if (client.phone != null) pw.Text(client.phone!, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        if (client.addressLine1 != null) pw.Text(client.addressLine1!, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),

        pw.SizedBox(height: 28),

        // Table header
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300)),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(flex: 5, child: pw.Text('Description', style: _th)),
              pw.Expanded(flex: 1, child: pw.Text('Qty', style: _th, textAlign: pw.TextAlign.right)),
              pw.Expanded(flex: 2, child: pw.Text('Price', style: _th, textAlign: pw.TextAlign.right)),
              pw.Expanded(flex: 2, child: pw.Text('Amount', style: _th, textAlign: pw.TextAlign.right)),
            ],
          ),
        ),

        for (final item in items)
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 10),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200)),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(flex: 5, child: pw.Text(item.description, style: const pw.TextStyle(fontSize: 10))),
                pw.Expanded(
                  flex: 1,
                  child: pw.Text(
                    item.quantity.toString(),
                    style: const pw.TextStyle(fontSize: 10),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
                pw.Expanded(
                  flex: 2,
                  child: pw.Text(
                    formatMoney(item.unitPrice, symbol: symbol),
                    style: const pw.TextStyle(fontSize: 10),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
                pw.Expanded(
                  flex: 2,
                  child: pw.Text(
                    formatMoney(item.amount, symbol: symbol),
                    style: const pw.TextStyle(fontSize: 10),
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
                  _totalRow('Discount', '- ${formatMoney(invoice.discountAmount, symbol: symbol)}'),
                if (invoice.vatAmount > 0)
                  _totalRow('VAT (${invoice.vatRate}%)', formatMoney(invoice.vatAmount, symbol: symbol)),
                pw.Container(
                  margin: const pw.EdgeInsets.only(top: 6),
                  padding: const pw.EdgeInsets.symmetric(vertical: 8),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(top: pw.BorderSide(color: PdfColors.black, width: 1.2)),
                  ),
                  child: _totalRow(
                    'Total',
                    formatMoney(invoice.total, symbol: symbol),
                    bold: true,
                  ),
                ),
                if (invoice.amountPaid > 0)
                  _totalRow('Paid', formatMoney(invoice.amountPaid, symbol: symbol)),
                if (invoice.total - invoice.amountPaid > 0.001)
                  _totalRow(
                    'Balance due',
                    formatMoney(invoice.total - invoice.amountPaid, symbol: symbol),
                    bold: true,
                  ),
              ],
            ),
          ),
        ),

        if (invoice.notes != null && invoice.notes!.isNotEmpty) ...[
          pw.SizedBox(height: 32),
          pw.Text('NOTES', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600, letterSpacing: 0.8)),
          pw.SizedBox(height: 6),
          pw.Text(invoice.notes!, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800)),
        ],

        pw.Spacer(),
        pw.SizedBox(height: 24),
        pw.Text(
          'Powered by Envoice',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey400),
          textAlign: pw.TextAlign.center,
        ),
      ],
    ),
  );

  return doc.save();
}

final _th = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600);

pw.Widget _totalRow(String label, String value, {bool bold = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: bold ? 11 : 10,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: bold ? 11 : 10,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ],
    ),
  );
}

String _fmt(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
