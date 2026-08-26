import 'dart:math';

/// The client facts Tracer expects alongside an event.
///
/// The field names come from the browser SDK, because that is the only client
/// of this ingest whose payload could be observed. Off the web they are filled
/// with the nearest honest equivalent rather than left out: a field the server
/// expects and does not get is a worse guess than a field it gets and ignores.
///
/// Kept behind an interface so the payload builder can be tested without a
/// browser, and so desktop can supply its own values.
abstract class TracerClientFacts {
  /// Creates facts.
  const TracerClientFacts();

  /// Stable per-installation identifier, persisted across reloads.
  String get deviceId;

  /// Identifier of the current page session, new on every load.
  String get sessionUuid;

  /// `location.host` on the web; elsewhere the operating system's name, which
  /// is the closest thing to «where this ran» that the field can carry.
  String get host;

  /// Screen width in CSS pixels.
  int get screenWidth;

  /// Screen height in CSS pixels.
  int get screenHeight;

  /// `screen.orientation.angle`, or 0 where the browser does not report it.
  int get screenOrientationAngle;

  /// `document.visibilityState`, either `visible` or `hidden`.
  String get documentVisibilityState;
}

/// Generates a random version-4 UUID.
///
/// Written out rather than pulled in as a dependency: it is nine lines, and a
/// crash reporter should add as little as possible to the applications that
/// carry it.
String randomUuid([Random? random]) {
  final Random rng = random ?? Random.secure();
  final List<int> bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final String hex =
      bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
