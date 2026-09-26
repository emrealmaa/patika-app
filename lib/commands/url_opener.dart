import 'package:url_launcher/url_launcher.dart';

/// URL açma soyutlaması (tel:, sms:) - testlerde açılan adres doğrulanabilsin.
typedef UrlOpener = Future<bool> Function(Uri uri);

Future<bool> defaultOpenUrl(Uri uri) => launchUrl(uri);
