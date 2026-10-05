import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

/// Publish a verified same-filesystem temporary file without overwriting an
/// unrelated file created between validation and commit.
Future<File> publishFileWithoutReplacing(File source, String destination) async {
  if (Platform.isWindows) {
    final move = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<Int32 Function(Pointer<Utf16>, Pointer<Utf16>), int Function(Pointer<Utf16>, Pointer<Utf16>)>('MoveFileW');
    String windowsPath(String path) {
      final absolute = File(path).absolute.path;
      if (absolute.startsWith(r'\\?\')) return absolute;
      if (absolute.startsWith(r'\\')) {
        return '${r'\\?\UNC\'}${absolute.substring(2)}';
      }
      return '${r'\\?\'}$absolute';
    }

    final from = windowsPath(source.path).toNativeUtf16();
    final to = windowsPath(destination).toNativeUtf16();
    try {
      if (move(from, to) == 0) {
        throw FileSystemException('无法提交文件，目标可能已经存在', destination);
      }
    } finally {
      calloc.free(from);
      calloc.free(to);
    }
  } else {
    final library = Platform.isAndroid
        ? DynamicLibrary.open('libc.so')
        : Platform.isLinux
            ? DynamicLibrary.open('libc.so.6')
            : DynamicLibrary.process();
    final from = source.absolute.path.toNativeUtf8();
    final to = File(destination).absolute.path.toNativeUtf8();
    try {
      final int result;
      if (Platform.isAndroid) {
        // Android's emulated storage does not support hard links. Linux
        // renameat2(RENAME_NOREPLACE) is atomic on those filesystems too.
        final syscall = library.lookupFunction<IntPtr Function(IntPtr, Int32, Pointer<Utf8>, Int32, Pointer<Utf8>, Uint32),
            int Function(int, int, Pointer<Utf8>, int, Pointer<Utf8>, int)>('syscall');
        final number = switch (Abi.current()) {
          Abi.androidArm64 => 276,
          Abi.androidArm => 382,
          Abi.androidX64 => 316,
          Abi.androidIA32 => 353,
          _ => throw UnsupportedError('Unsupported Android ABI'),
        };
        result = syscall(number, -100, from, -100, to, 1);
      } else {
        final link = library.lookupFunction<Int32 Function(Pointer<Utf8>, Pointer<Utf8>), int Function(Pointer<Utf8>, Pointer<Utf8>)>('link');
        result = link(from, to);
      }
      if (result != 0) {
        throw FileSystemException('无法提交文件，目标可能已经存在或文件系统不支持安全提交', destination);
      }
    } finally {
      calloc.free(from);
      calloc.free(to);
    }
    if (!Platform.isAndroid) await source.delete();
  }
  return File(destination);
}
