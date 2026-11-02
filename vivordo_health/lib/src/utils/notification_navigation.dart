/// Where a notification opens: a tab of the main app (5 opens Vivordo AI)
/// and a screen pushed over it, if any. [type] picks a part of the screen:
/// Circle's challenge and achievement pushes open its Challenges tab
/// (where the achievements card is).
({int tab, String? push}) notificationDestination(
  String? screen, {
  String? type,
}) => switch (screen) {
  'scan' => (tab: 2, push: null),
  'ai_chat' => (tab: 5, push: null),
  'circle'
      when type != null &&
          (type.startsWith('challenge_') || type == 'achievement_unlocked') =>
    (tab: 0, push: '/circle/challenges'),
  'circle' => (tab: 0, push: '/circle'),
  'fitness' => (tab: 3, push: null),
  'calendar' => (tab: 1, push: null),
  _ => (tab: 0, push: null),
};
