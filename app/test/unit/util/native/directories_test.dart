import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/util/native/directories.dart';

void main() {
  group('Windows 默认接收目录', () {
    test('优先使用系统 Downloads API 返回的完整路径', () {
      final candidates = buildWindowsDestinationDirectoryCandidates(
        downloadsDirectory: r'D:/Redirected Downloads',
        documentsDirectory: r'C:\Users\33535\Documents',
        environment: const {
          'USERPROFILE': r'C:\Users\33535',
          'HOMEDRIVE': 'C:',
          'HOMEPATH': r'\Users\33535',
        },
      );

      expect(candidates.first, r'D:\Redirected Downloads');
    });

    test('USERPROFILE 回退始终保留盘符', () {
      final candidates = buildWindowsDestinationDirectoryCandidates(
        downloadsDirectory: null,
        documentsDirectory: r'C:\Users\33535\Documents',
        environment: const {
          'USERPROFILE': r'C:\Users\33535',
          'HOMEPATH': r'\Users\33535',
        },
      );

      expect(candidates.first, r'C:\Users\33535\Downloads');
      expect(candidates, isNot(contains(r'\Users\33535\Downloads')));
      expect(candidates.any((path) => path.startsWith('/Users/')), isFalse);
    });

    test('没有 USERPROFILE 时组合 HOMEDRIVE 和 HOMEPATH', () {
      final candidates = buildWindowsDestinationDirectoryCandidates(
        downloadsDirectory: null,
        documentsDirectory: null,
        environment: const {
          'HOMEDRIVE': 'E:',
          'HOMEPATH': r'\Users\localshare',
        },
      );

      expect(candidates, [r'E:\Users\localshare\Downloads']);
    });

    test('不会把缺少盘符的 HOMEPATH 当成完整目录', () {
      final candidates = buildWindowsDestinationDirectoryCandidates(
        downloadsDirectory: null,
        documentsDirectory: r'C:\Users\33535\Documents',
        environment: const {
          'HOMEPATH': r'\Users\33535',
        },
      );

      expect(candidates, [r'C:\Users\33535\Documents\LocalShare']);
    });
  });
}
