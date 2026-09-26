import 'dart:io';
import 'dart:typed_data';

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
/// Throws [StateError] with a clear message on failure so UI can show a snackbar.
Future<void> shareInvoicePdf({
  required List<int> bytes,
  required String filename,
  String? text,
}) async {
  File? file;
  try {
    final dir = await getTemporaryDirectory();
    file = File(p.join(dir.path, filename));
    await file.writeAsBytes(
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      flush: true,
    );

    final result = await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: filename)],
      text: text,
      subject: filename.replaceAll('.pdf', ''),
    );

    // User dismissed the sheet without sharing — not an error.
    if (result.status == ShareResultStatus.dismissed) return;
  } catch (e) {
    throw StateError('Could not share invoice PDF: $e');
  } finally {
    // Best-effort cleanup; ignore failures.
    try {
      if (file != null && await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}

Future<void> shareText(String text) async {
  try {
    final result = await Share.share(text);
    if (result.status == ShareResultStatus.dismissed) return;
  } catch (e) {
    throw StateError('Could not open share sheet: $e');
  }
}

String _fmt(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
