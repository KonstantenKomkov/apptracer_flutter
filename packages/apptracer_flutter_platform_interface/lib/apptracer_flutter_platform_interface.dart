/// Platform interface and shared data models for `apptracer_flutter`, an
/// unofficial Flutter integration with the Tracer service (apptracer.ru).
///
/// Application code should depend on `apptracer_flutter` instead. This package
/// exists so that platform implementations and the app-facing package can
/// evolve independently.
library;

export 'src/method_channel_tracer.dart';
export 'src/models/dart_stack_frame.dart';
export 'src/models/dart_stack_trace.dart';
export 'src/models/tracer_breadcrumb.dart';
export 'src/models/tracer_event.dart';
export 'src/models/tracer_options.dart';
export 'src/models/tracer_severity.dart';
export 'src/synthetic_issue_key.dart';
export 'src/tracer_platform.dart';
