import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/util/native/file_saver.dart';
import 'package:saf_stream/saf_stream_platform_interface.dart';

class FakeSaf extends SafStreamPlatform {
  FakeSaf(this.name);
  final String name;
  int writes = 0;
  @override
  Future<SafWriteStreamInfo> startWriteStream(String treeUri, String fileName, String mime, {bool? overwrite}) async =>
      SafWriteStreamInfo('session', SafNewFile(Uri.parse('content://test/new-file'), name));
  @override
  Future<void> writeChunk(String session, Uint8List data) async {
    writes++;
  }

  @override
  Future<void> endWriteStream(String session) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('SAF refuses a provider-renamed file and removes only its new document', () async {
    final original = SafStreamPlatform.instance;
    final saf = FakeSaf('main (2).dart');
    SafStreamPlatform.instance = saf;
    addTearDown(() {
      SafStreamPlatform.instance = original;
    });
    String? removed;
    const channel = MethodChannel('org.localsend.localsend_app/localsend');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'deleteTaskDocument') {
        removed = (call.arguments as Map)['uri'] as String;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });
    await expectLater(
        saveFile(
            destinationPath: 'content://test/main.dart',
            documentUri: 'content://test/parent',
            name: 'main.dart',
            saveToGallery: false,
            isImage: false,
            stream: Stream.value(Uint8List.fromList([1, 2, 3])),
            androidSdkInt: 30,
            lastModified: null,
            lastAccessed: null,
            onProgress: (_) {},
            preserveName: true,
            expectedSize: 3),
        throwsA(isA<Exception>()));
    expect(saf.writes, 0);
    expect(removed, 'content://test/new-file');
  });
}
