import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:vivordo_health/src/services/achievement_unlock_service.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

/// A notification-style banner for new achievements: drops in from the top,
/// leaves by itself, swipes up to close, and opens the celebration on tap.
/// Several unlocks at once share one banner.
class AchievementBanner extends StatefulWidget {
  const AchievementBanner({
    super.key,
    required this.unlocks,
    required this.onOpen,
    required this.onDismissed,
  });

  final List<AchievementUnlock> unlocks;
  final VoidCallback onOpen;

  /// After it has slid away; the owner removes it then.
  final VoidCallback onDismissed;

  @override
  State<AchievementBanner> createState() => _AchievementBannerState();
}

class _AchievementBannerState extends State<AchievementBanner>
    with SingleTickerProviderStateMixin {
  late final _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  Timer? _timer;
  bool _leaving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_slide.status != AnimationStatus.dismissed || _leaving) return;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _slide.value = 1;
    } else {
      _slide.forward();
    }
    // VoiceOver users need longer to reach it.
    _timer = Timer(
      Duration(seconds: MediaQuery.accessibleNavigationOf(context) ? 10 : 4),
      _leave,
    );
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    _timer?.cancel();
    if (mounted && !MediaQuery.disableAnimationsOf(context)) {
      await _slide.reverse();
    }
    widget.onDismissed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final first = widget.unlocks.first;
    final count = widget.unlocks.length;
    final subtitle = count == 1
        ? 'Achievement unlocked'
        : '$count achievements unlocked';
    final title = widget.unlocks.map((unlock) => unlock.name).join(', ');
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: SlideTransition(
          position: Tween(begin: const Offset(0, -1.4), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: _slide, curve: Curves.easeOutCubic),
              ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Semantics(
              liveRegion: true,
              button: true,
              label: '$subtitle: $title. Double tap to view.',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () {
                  widget.onOpen();
                  _leave();
                },
                onVerticalDragEnd: (details) {
                  if ((details.primaryVelocity ?? 0) < 0) _leave();
                },
                child: Material(
                  color: colors.card,
                  elevation: 8,
                  shadowColor: Colors.black38,
                  borderRadius: BorderRadius.circular(22),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                      child: Row(
                        children: [
                          Image.asset(first.badgeAsset, width: 44, height: 44),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colors.textSecondary,
                                  ),
                                ),
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: colors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            CupertinoIcons.chevron_right,
                            size: 15,
                            color: colors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
