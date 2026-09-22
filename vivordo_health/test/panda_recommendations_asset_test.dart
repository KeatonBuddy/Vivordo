import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/panda_recommendations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled catalog loads without truncating HTTPS links', () async {
    final recommendations = await PandaRecommendations.reload();
    expect(recommendations, isNotEmpty);
    final focus = PandaRecommendations.byId('music_calm_focus');
    expect(focus, isNotNull);
    expect(
      focus!.deepLink,
      'https://open.spotify.com/playlist/37i9dQZF1DWZeKCadgRdKQ',
    );
  });
}
