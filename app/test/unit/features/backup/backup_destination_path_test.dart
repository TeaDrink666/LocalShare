import 'package:localsend_app/features/backup/domain/media_snapshot.dart';
import 'package:localsend_app/features/backup/receiver/backup_destination_path.dart';
import 'package:test/test.dart';

void main() {
  test('flattens images into the image directory', () {
    expect(
      backupDestinationFileName(
        _media(
          relativePath: '我的文件/收藏空间/',
          displayName: '7658117710505400250.jpg',
          mimeType: 'image/jpeg',
        ),
      ),
      '图片/7658117710505400250.jpg',
    );
  });

  test('flattens videos into the video directory', () {
    expect(
      backupDestinationFileName(
        _media(
          relativePath: 'DCIM/Camera/',
          displayName: 'VID_20260714_191543.mp4',
          mimeType: 'video/mp4',
        ),
      ),
      '视频/VID_20260714_191543.mp4',
    );
  });

  test('rejects media outside the supported backup types', () {
    expect(
      () => backupDestinationFileName(
        _media(
          relativePath: 'Download/',
          displayName: 'note.txt',
          mimeType: 'text/plain',
        ),
      ),
      throwsArgumentError,
    );
  });
}

MediaSnapshotItem _media({
  required String relativePath,
  required String displayName,
  required String mimeType,
}) {
  return MediaSnapshotItem(
    mediaKey: 'external:1',
    relativePath: relativePath,
    displayName: displayName,
    sizeBytes: 1,
    modifiedAtSeconds: 1,
    generationModified: 1,
    mimeType: mimeType,
  );
}
