import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

class Metadata {
  String? device;
  String? locale;

  Metadata(this.device, this.locale);

  Metadata.create()
    : this(
        kIsWeb ? "web" : Platform.operatingSystem,
        kIsWeb ? web.window.navigator.language : Platform.localeName,
      );

  Map<String, dynamic> toMap() {
    return {'device': device, 'locale': locale};
  }
}
