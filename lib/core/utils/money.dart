import 'package:intl/intl.dart';

String formatMoney(
  double amount, {
  String symbol = '₦',
  String locale = 'en_NG',
}) {
  final formatter = NumberFormat.currency(
    locale: locale,
    symbol: symbol,
    decimalDigits: 2,
  );
  return formatter.format(amount);
}

String formatMoneyCompact(double amount, {String symbol = '₦'}) {
  if (amount.abs() >= 1000000) {
    return '$symbol${(amount / 1000000).toStringAsFixed(1)}m';
  }
  if (amount.abs() >= 1000) {
    return '$symbol${(amount / 1000).toStringAsFixed(1)}k';
  }
  return formatMoney(amount, symbol: symbol);
}
