bool whoopReconnectRequired(String code, Object? details) {
  if (code != 'failed-precondition' || details is! Map) return false;
  return details['whoopReconnectRequired'] == true;
}
