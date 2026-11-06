import 'package:flutter/material.dart';

class ConnectivityBadge extends StatelessWidget {
  const ConnectivityBadge({
    super.key,
    this.isOnline = true,
    this.compact = false,
  });

  final bool isOnline;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = isOnline ? const Color(0xFF059669) : Colors.orange.shade700;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 11,
        vertical: compact ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Text(
            isOnline ? 'Online' : 'Offline',
            style: TextStyle(
              color: color,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
