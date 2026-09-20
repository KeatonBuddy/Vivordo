import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:vivordo_health/widgets/privacy_support_links.dart';

void main() {
  final original = UrlLauncherPlatform.instance;
  setUp(() => UrlLauncherPlatform.instance = _UnavailableLauncher());
  tearDown(() => UrlLauncherPlatform.instance = original);
  testWidgets('settings exposes policies and a usable support fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PrivacySupportLinks())),
    );
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Terms & Conditions'), findsOneWidget);
    expect(find.text('Contact Support'), findsOneWidget);
    await tester.tap(find.text('Contact Support'));
    await tester.pumpAndSettle();
    expect(find.text('Could not open link'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            (widget.data?.contains(vivordoSupportEmail) ?? false),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

class _UnavailableLauncher extends UrlLauncherPlatform {
  @override
  Null get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async => false;
}
