import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../db/app_database.dart';
import 'money.dart';

/// Builds a polite follow-up message the owner can send on WhatsApp.
String buildReminderMessage({
  required Invoice invoice,
  required String clientName,
  required String? businessName,
}) {
  final balance = invoice.total - invoice.amountPaid;
  final amount = formatMoney(
    balance > 0.001 ? balance : invoice.total,
    symbol: invoice.currencySymbol,
  );
  final due = invoice.dueDate != null
      ? ' due ${_fmt(invoice.dueDate!)}'
      : '';
  final biz = (businessName != null && businessName.trim().isNotEmpty)
      ? businessName.trim()
      : 'us';

  return 'Hi $clientName, just following up on invoice ${invoice.number}'
      '$due for $amount. Please let me know if you have any questions. '
      'Thank you, $biz.';
}

String buildInvoiceShareMessage({
  required Invoice invoice,
  required String clientName,
  required String? businessName,
}) {
  final amount = formatMoney(invoice.total, symbol: invoice.currencySymbol);
  final biz = (businessName != null && businessName.trim().isNotEmpty)
      ? businessName.trim()
      : 'us';
  final due = invoice.dueDate != null
      ? ' Due ${_fmt(invoice.dueDate!)}.'
      : '';

  return 'Hi $clientName, please find invoice ${invoice.number} for $amount.'
      '$due Thank you, $biz.';
}

/// Writes PDF bytes to a temp file and opens the system share sheet
/// (WhatsApp, Files, Gmail, etc.).
Future<void> shareInvoicePdf({
  required List<int> bytes,
  required String filename,
  String? text,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File(p.join(dir.path, filename));
  await file.writeAsBytes(bytes, flush: true);

  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'application/pdf', name: filename)],
    text: text,
    subject: filename.replaceAll('.pdf', ''),
  );
}

Future<void> shareText(String text) {
  return Share.share(text);
}

String _fmt(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
