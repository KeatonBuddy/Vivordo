import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

class WhoopSourceBadge extends StatelessWidget {
  const WhoopSourceBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = context.vivordoColors.textSecondary;
    return Semantics(
      label: 'Data from WHOOP',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 5 : 7,
          vertical: compact ? 2 : 3,
        ),
        decoration: BoxDecoration(
          color: foreground.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: foreground.withValues(alpha: .16)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              dark
                  ? 'assets/whoop_puck_white.svg'
                  : 'assets/whoop_puck_black.svg',
              width: 30,
              height: 30,
              excludeFromSemantics: true,
            ),
            if (!compact) ...[
              const SizedBox(width: 4),
              Text(
                'WHOOP',
                style: TextStyle(
                  color: foreground,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
