import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class StatusBadge extends StatelessWidget {
  final String status;

  const StatusBadge({super.key, required this.status});

  Color get _fg {
    switch (status) {
      case 'paid':
        return AppColors.success;
      case 'overdue':
      case 'voided':
        return AppColors.danger;
      case 'partial':
        return AppColors.warning;
      case 'sent':
        return AppColors.systemBlue;
      default:
        return AppColors.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = status.isEmpty
        ? 'DRAFT'
        : status[0].toUpperCase() + status.substring(1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: _fg,
          height: 1.2,
        ),
      ),
    );
  }
}
