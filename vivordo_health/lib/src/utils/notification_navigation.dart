/// Where a notification opens, with the main app beneath it. [type] picks
/// a part of the screen: Circle's challenge and achievement pushes open its
/// Challenges tab (where the achievements card is).
List<String> notificationRouteStack(String? screen, {String? type}) {
  final destination = switch (screen) {
    'scan' => '/scan',
    'ai_chat' => '/ai-chat',
    'circle'
        when type != null &&
            (type.startsWith('challenge_') || type == 'achievement_unlocked') =>
      '/circle/challenges',
    'circle' => '/circle',
    'fitness' => '/fitness',
    'calendar' => '/calendar',
    _ => '/home',
  };

  if (destination == '/home') return const ['/home'];
  return ['/home', destination];
}
