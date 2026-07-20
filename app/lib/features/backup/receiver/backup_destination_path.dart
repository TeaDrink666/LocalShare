import 'package:localsend_app/features/backup/domain/media_snapshot.dart';

const backupImageDirectoryName = '图片';
const backupVideoDirectoryName = '视频';

/// Maps a phone media item to its flat receiver-side category path.
///
/// The original MediaStore directory is intentionally ignored. Name
/// collisions are handled by the receiver's existing numbered-name logic.
String backupDestinationFileName(MediaSnapshotItem item) {
  final category = switch (item.mimeType.toLowerCase()) {
    final mimeType when mimeType.startsWith('image/') => backupImageDirectoryName,
    final mimeType when mimeType.startsWith('video/') => backupVideoDirectoryName,
    _ => throw ArgumentError.value(
        item.mimeType,
        'item.mimeType',
        'Backup media must be an image or video',
      ),
  };
  return '$category/${item.displayName}';
}
