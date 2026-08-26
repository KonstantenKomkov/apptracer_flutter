/// Severity levels understood by Tracer.
///
/// The values map 1:1 onto `ru.ok.tracer.Severity` on Android and onto
/// `OKTracer.ReportSeverity` on iOS, and onto the Sentry `level` field for the
/// Sentry-protocol transport.
enum TracerSeverity {
  /// Highest severity. On Android and iOS this level counts against the
  /// crash-free metric, so reserve it for genuinely fatal conditions.
  fatal('fatal'),

  /// An error that the application handled but should not have hit.
  error('error'),

  /// A recoverable problem worth investigating.
  warning('warning'),

  /// Noteworthy, but not a problem.
  notice('notice'),

  /// Informational.
  info('info'),

  /// Diagnostic detail, normally filtered out server side.
  debug('debug');

  const TracerSeverity(this.wireName);

  /// The lowercase name used on the wire and by both native SDKs.
  final String wireName;

  /// Parses [wireName] back into a [TracerSeverity].
  ///
  /// Returns `null` when [value] is not a known severity.
  static TracerSeverity? fromWireName(String value) {
    for (final severity in TracerSeverity.values) {
      if (severity.wireName == value) {
        return severity;
      }
    }
    return null;
  }
}
