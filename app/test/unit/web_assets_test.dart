import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('embedded web gateway assets', () {
    const assets = <String>[
      'assets/web/index.html',
      'assets/web/main.js',
      'assets/web/error-403.html',
      'assets/web/receive.html',
      'assets/web/receive.js',
    ];

    for (final asset in assets) {
      test('$asset is bundled and non-empty', () async {
        final contents = await rootBundle.loadString(asset);
        expect(contents.trim(), isNotEmpty);
      });
    }

    test('browser upload client targets the LocalSend v2 protocol', () async {
      final script = await rootBundle.loadString('assets/web/receive.js');
      expect(script, contains("const BASE_URL = '/api/localsend/v2'"));
      expect(script, contains('/prepare-upload'));
      expect(script, contains('/upload?'));
    });

    test('browser download client renders file metadata without innerHTML',
        () async {
      final script = await rootBundle.loadString('assets/web/main.js');

      expect(script, isNot(contains('innerHTML')));
      expect(script, contains('document.createTextNode'));
      expect(script, contains("createFileCell('file-name-cell', fileName)"));
    });

    test('browser download page prefers one ZIP with a sequential fallback',
        () async {
      final html = await rootBundle.loadString('assets/web/index.html');
      final script = await rootBundle.loadString('assets/web/main.js');

      expect(html, contains('id="download-all-button"'));
      expect(html, contains('role="progressbar"'));
      expect(script, contains('function beginDownloadAll()'));
      expect(script, contains("BASE_URL + '/download-all?sessionId='"));
      expect(script, contains('function triggerArchiveDownload(url)'));
      expect(
        script,
        contains("link.setAttribute('download', 'LocalShare-files.zip')"),
      );
      expect(script, contains('startQueuedDownload(0)'));
      expect(script, contains('function triggerBrowserDownload(item)'));
      expect(script, contains("link.setAttribute('download', '')"));
      expect(script, isNot(contains('responseType')));
    });
  });
}
