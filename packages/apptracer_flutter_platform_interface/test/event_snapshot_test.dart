import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('event and breadcrumb snapshots survive caller edits', () {
    final keys = {'key': 'original'};
    final data = {'crumb': 'original'};
    final crumb = TracerBreadcrumb(message: 'step', data: data);
    final trail = [crumb];
    final frames = [const DartStackFrame(raw: 'frame')];
    final event = TracerEvent(
      exceptionType: 'Error',
      message: 'failure',
      stackTrace: DartStackTrace(raw: 'trace', frames: frames),
      customKeys: keys,
      breadcrumbs: trail,
    );
    keys.clear();
    data.clear();
    trail.clear();
    frames.clear();

    expect(event.customKeys, {'key': 'original'});
    expect(event.breadcrumbs.single.data, {'crumb': 'original'});
    expect(event.stackTrace.frames.single.raw, 'frame');
    expect(event.customKeys.clear, throwsUnsupportedError);
    expect(event.breadcrumbs.clear, throwsUnsupportedError);
    expect(crumb.data.clear, throwsUnsupportedError);
    expect(event.stackTrace.frames.clear, throwsUnsupportedError);
  });

  test(
      'copyWith snapshots replacements and redacts each Flutter field independently',
      () {
    final event = TracerEvent(
      exceptionType: 'Error',
      message: 'failure',
      stackTrace: DartStackTrace.empty,
      library: 'widgets',
      context: 'private',
    );
    final keys = {'new': 'value'};
    final crumb = TracerBreadcrumb(message: 'step').copyWith(data: keys);
    final crumbs = [crumb];
    final copy = event.copyWith(customKeys: keys, breadcrumbs: crumbs);
    keys.clear();
    crumbs.clear();
    expect(copy.customKeys, {'new': 'value'});
    expect(copy.breadcrumbs.single.data, {'new': 'value'});
    expect(copy.library, 'widgets');
    expect(copy.context, 'private');
    final noLibrary = copy.copyWith(removeLibrary: true, library: 'ignored');
    expect(noLibrary.toMap().containsKey('library'), isFalse);
    expect(noLibrary.context, 'private');
    final noContext = copy.copyWith(removeContext: true, context: 'ignored');
    expect(noContext.toMap().containsKey('context'), isFalse);
    expect(noContext.library, 'widgets');
  });
}
