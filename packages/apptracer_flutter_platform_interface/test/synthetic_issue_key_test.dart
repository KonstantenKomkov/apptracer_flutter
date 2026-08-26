import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

DartStackFrame _frame(String? member, {String? virtualAddress, int? line}) =>
    DartStackFrame(
      raw: member ?? virtualAddress ?? '',
      member: member,
      uri: member == null ? null : 'package:example/main.dart',
      line: line,
      virtualAddress: virtualAddress,
    );

void main() {
  group('SyntheticIssueKey', () {
    test('uses the error type and the innermost named frame', () {
      final String key = SyntheticIssueKey.forError(
        exceptionType: 'StateError',
        frames: <DartStackFrame>[_frame('MyPage.build')],
      );

      expect(key, 'dart/StateError/MyPage.build');
    });

    test('ignores the line number, so a code edit keeps one group', () {
      String keyAtLine(int line) => SyntheticIssueKey.forError(
            exceptionType: 'StateError',
            frames: <DartStackFrame>[_frame('MyPage.build', line: line)],
          );

      expect(keyAtLine(135), keyAtLine(148));
    });

    test('separates errors of different types thrown from one call site', () {
      // The live-run failure this exists for: two errors sharing a top frame
      // must not share a group.
      const String member = '_HomePageState.build.<anonymous closure>';
      final String stateError = SyntheticIssueKey.forError(
        exceptionType: 'StateError',
        frames: <DartStackFrame>[_frame(member)],
      );
      final String timeout = SyntheticIssueKey.forError(
        exceptionType: 'TimeoutException',
        frames: <DartStackFrame>[_frame(member)],
      );

      expect(stateError, isNot(timeout));
    });

    test('skips the asynchronous suspension marker', () {
      final String key = SyntheticIssueKey.forError(
        exceptionType: 'TimeoutException',
        frames: <DartStackFrame>[
          DartStackFrame.asynchronousSuspension('<asynchronous suspension>'),
          _frame('MyPage.build'),
        ],
      );

      // 'dart/TimeoutException/MyPage.build' — 34 символа, то есть ключ
      // ужимается; важно, что он выведен из именованного кадра, а не
      // свалился в запасной вариант «только тип».
      expect(key, isNot('dart/TimeoutException'));
      expect(key, contains('MyPage.build'));
    });

    test('falls back to the virtual address of an obfuscated frame', () {
      final String key = SyntheticIssueKey.forError(
        exceptionType: 'StateError',
        frames: <DartStackFrame>[_frame(null, virtualAddress: '2cc2f0')],
      );

      expect(key, 'dart/StateError/virt+2cc2f0');
    });

    test('falls back to the type alone when there are no frames', () {
      expect(
        SyntheticIssueKey.forError(
          exceptionType: 'StateError',
          frames: const <DartStackFrame>[],
        ),
        'dart/StateError',
      );
    });

    test('stays within the 32-character limit', () {
      final String key = SyntheticIssueKey.forError(
        exceptionType: 'TimeoutException',
        frames: <DartStackFrame>[
          _frame('_HomePageState.build.<anonymous closure>'),
        ],
      );

      expect(key.length, lessThanOrEqualTo(SyntheticIssueKey.maxLength));
      expect(key, startsWith('d/'));
      // The tail of the member survives, because the method name says more
      // than the class prefix it hangs off.
      expect(key, contains('closure>'));
    });

    test('two members trimmed to the same tail still differ', () {
      String keyFor(String member) => SyntheticIssueKey.forError(
            exceptionType: 'StateError',
            frames: <DartStackFrame>[_frame(member)],
          );

      final String first =
          keyFor('_FirstVeryLongStateName.build.<anonymous closure>');
      final String second =
          keyFor('_OtherVeryLongStateName.build.<anonymous closure>');

      expect(first.length, lessThanOrEqualTo(SyntheticIssueKey.maxLength));
      expect(second.length, lessThanOrEqualTo(SyntheticIssueKey.maxLength));
      expect(first, isNot(second));
    });

    test('is stable across calls, unlike a seeded hashCode', () {
      String key() => SyntheticIssueKey.forError(
            exceptionType: 'FormatException',
            frames: <DartStackFrame>[
              _frame('_HomePageState.build.<anonymous closure>'),
            ],
          );

      expect(key(), key());
    });
  });
}
