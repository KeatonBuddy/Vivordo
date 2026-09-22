List<String> notificationRouteStack(String? screen) {
  final destination = switch (screen) {
    'scan' => '/scan',
    'ai_chat' => '/ai-chat',
    'circle' => '/circle',
    'fitness' => '/fitness',
    'calendar' => '/calendar',
    _ => '/home',
  };

  if (destination == '/home') return const ['/home'];
  return ['/home', destination];
}
