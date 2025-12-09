class Preferences {
  final String timezone;
  final String locale;
  final String units;
  final bool notificationsEnabled;

  Preferences({
    required this.timezone,
    required this.locale,
    required this.units,
    required this.notificationsEnabled,
  });

  factory Preferences.fromMap(Map<String, dynamic> data) {
    return Preferences(
      timezone: data['timezone'],
      locale: data['locale'],
      units: data['units'],
      notificationsEnabled: data['notificationsEnabled'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "timezone": timezone,
      "locale": locale,
      "units": units,
      "notificationEnabled": notificationsEnabled,
    };
  }
}
