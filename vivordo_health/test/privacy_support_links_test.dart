import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Mocks the platform interface the app gets through url_launcher.
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:vivordo_health/widgets/privacy_support_links.dart';

void main() {
  final original = UrlLauncherPlatform.instance;
  setUp(() => UrlLauncherPlatform.instance = _UnavailableLauncher());
  tearDown(() => UrlLauncherPlatform.instance = original);
  testWidgets('support link falls back to a copyable address', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openVivordoLink(
                context,
                Uri(scheme: 'mailto', path: vivordoSupportEmail),
              ),
              child: const Text('Contact support'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Contact support'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't open link"), findsOneWidget);
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
