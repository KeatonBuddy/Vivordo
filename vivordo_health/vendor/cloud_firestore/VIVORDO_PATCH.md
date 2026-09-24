# Local iOS transaction safety patch (upstream cloud_firestore 6.8.0)

The iOS transaction stream handler now returns a native deadline-exceeded
error immediately on timeout instead of falling through to a successful commit.
The transaction read bridge converts only the known use-after-commit assertion
to an `aborted` Flutter error; unrelated native exceptions are rethrown.

This override is tracked in pubspec.yaml. Do not remove it during dependency
upgrades until equivalent upstream protection is verified. License retained.
Both CocoaPods and Swift Package Manager consume this package's iOS sources.

Device validation: build release, connect a Bluetooth heart-rate monitor,
background/lock during syncing for over 30 seconds, then resume. Repeat with
poor connectivity. Verify saved readings and goal notifications after resume.
Dart tests do not exercise native suspension or the Objective-C exception path.
