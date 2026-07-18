import 'package:localsend_app/features/web_transfer/windows_safe_archive_path.dart';
import 'package:test/test.dart';

void main() {
  group('createWindowsSafeArchivePaths', () {
    test('preserves relative Unicode folders and ordinary names', () {
      final paths = createWindowsSafeArchivePaths(const [
        ArchivePathSource(
          id: 'photo',
          relativePath: 'DCIM/相机/旅行/夏天🌻.jpg',
        ),
      ]);

      expect(paths['photo'], 'DCIM/相机/旅行/夏天🌻.jpg');
    });

    test('sanitizes invalid characters, trailing dots/spaces, and devices', () {
      final paths = createWindowsSafeArchivePaths(const [
        ArchivePathSource(
          id: 'invalid',
          relativePath: 'CON/album<2026>/NUL.txt/photo?:*"|.jpg /back\\slash. ',
        ),
        ArchivePathSource(
          id: 'control',
          relativePath: 'AUX/control\u0001name.txt',
        ),
      ]);

      expect(
        paths['invalid'],
        '_CON/album_2026_/_NUL.txt/photo_____.jpg_/back_slash__',
      );
      expect(paths['control'], '_AUX/control_name.txt');
    });

    test('makes cleaned Windows path collisions stable and unique', () {
      const first = ArchivePathSource(
        id: 'question',
        relativePath: 'Camera/a?.jpg',
      );
      const second = ArchivePathSource(
        id: 'asterisk',
        relativePath: 'camera/A*.jpg',
      );

      final forward = createWindowsSafeArchivePaths(const [first, second]);
      final reverse = createWindowsSafeArchivePaths(const [second, first]);

      expect(forward, reverse);
      expect(forward['question'], matches(r'^Camera/a_~[0-9a-f]{8}\.jpg$'));
      expect(forward['asterisk'], matches(r'^camera/A_~[0-9a-f]{8}\.jpg$'));
      expect(
        forward['question']!.toLowerCase(),
        isNot(forward['asterisk']!.toLowerCase()),
      );
    });

    test('resolves identical original paths using the stable source ID', () {
      final paths = createWindowsSafeArchivePaths(const [
        ArchivePathSource(id: 'first', relativePath: 'same/photo.jpg'),
        ArchivePathSource(id: 'second', relativePath: 'same/photo.jpg'),
      ]);

      expect(paths.values.toSet(), hasLength(2));
      expect(
        paths.values,
        everyElement(matches(r'^same/photo~[0-9a-f]{8}\.jpg$')),
      );
    });

    test('turns absolute, traversal, empty, and repeated segments into files',
        () {
      final paths = createWindowsSafeArchivePaths(const [
        ArchivePathSource(id: 'odd', relativePath: '/../folder//..'),
        ArchivePathSource(id: 'empty', relativePath: ''),
      ]);

      expect(paths['odd'], '_/__/folder/_/__');
      expect(paths['empty'], '_');
    });

    test('rejects duplicate source IDs', () {
      expect(
        () => createWindowsSafeArchivePaths(const [
          ArchivePathSource(id: 'same', relativePath: 'one.jpg'),
          ArchivePathSource(id: 'same', relativePath: 'two.jpg'),
        ]),
        throwsArgumentError,
      );
    });
  });
}
