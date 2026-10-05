import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:common/api_route_builder.dart';
import 'package:common/constants.dart';
import 'package:common/model/dto/file_dto.dart';
import 'package:common/model/dto/info_dto.dart';
import 'package:common/model/dto/receive_request_response_dto.dart';
import 'package:common/model/file_type.dart';
import 'package:common/util/stream.dart';
import 'package:localsend_app/features/tasks/task_destination.dart';
import 'package:localsend_app/features/tasks/transfer_task.dart';
import 'package:localsend_app/features/web_transfer/streaming_zip_writer.dart';
import 'package:localsend_app/gen/assets.gen.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/state/send/web/web_send_file.dart';
import 'package:localsend_app/model/state/send/web/web_send_session.dart';
import 'package:localsend_app/model/state/send/web/web_send_state.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/network/server/controller/common.dart';
import 'package:localsend_app/provider/network/web_gateway/web_gateway_utils.dart';
import 'package:localsend_app/provider/progress_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/provider/task_provider.dart';
import 'package:localsend_app/util/byte_stream_slice.dart';
import 'package:localsend_app/util/http_byte_range.dart';
import 'package:localsend_app/util/simple_server.dart';
import 'package:uri_content/uri_content.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();
const _downloadAllRoute = '/api/localsend/v2/download-all';
const _downloadAllFileName = 'LocalShare-files.zip';

/// Handles the web download (app -> browser) routes on the independent web
/// gateway listener.
class WebGatewayController {
  final WebGatewayUtils gateway;
  final UriContent _uriContent;
  final _downloadTasks = <String>{};

  WebGatewayController(
    this.gateway, {
    UriContent? uriContent,
  }) : _uriContent = uriContent ?? UriContent();

  /// Installs all routes for receiving files.
  void installRoutes({
    required SimpleServerRouteBuilder router,
    required String alias,
    required String fingerprint,
  }) {
    router.get('/', (HttpRequest request) async {
      final state = gateway.getState();
      if (state.webSendState == null) {
        // There is no web send state
        return await request.respondAsset(403, Assets.web.error403);
      }

      return await request.respondAsset(200, Assets.web.index);
    });

    router.get('/main.js', (HttpRequest request) async {
      final state = gateway.getState();
      if (state.webSendState == null) {
        // There is no web send state
        return await request.respondAsset(403, Assets.web.error403);
      }

      return await request.respondAsset(200, Assets.web.main, 'text/javascript; charset=utf-8');
    });

    router.get('/i18n.json', (HttpRequest request) async {
      final state = gateway.getState();
      if (state.webSendState == null) {
        // There is no web send state
        return await request.respondJson(403, message: 'Web send not initialized.');
      }

      return await request.respondJson(200, body: {
        'waiting': t.web.waiting,
        'enterPin': t.web.enterPin,
        'invalidPin': t.web.invalidPin,
        'tooManyAttempts': t.web.tooManyAttempts,
        'rejected': t.web.rejected,
        'files': t.web.files,
        'fileName': t.web.fileName,
        'size': t.web.size,
      });
    });

    router.post(ApiRoute.prepareDownload.v2, (HttpRequest request) async {
      final state = gateway.getState();
      if (state.webSendState == null) {
        // There is no web send state
        return request.respondJson(403, message: 'Web send not initialized.');
      }

      final requestSessionId = request.uri.queryParameters['sessionId'];
      if (requestSessionId != null) {
        // Check if the user already has permission
        final session = gateway.getState().webSendState?.sessions[requestSessionId];
        if (session != null && session.responseHandler == null && session.ip == request.ip) {
          final deviceInfo = gateway.ref.read(deviceInfoProvider);
          return await request.respondJson(200,
              body: ReceiveRequestResponseDto(
                info: InfoDto(
                  alias: alias,
                  version: protocolVersion,
                  deviceModel: deviceInfo.deviceModel,
                  deviceType: deviceInfo.deviceType,
                  fingerprint: fingerprint,
                  download: true,
                ),
                sessionId: session.sessionId,
                files: {
                  for (final entry in state.webSendState!.files.entries) entry.key: entry.value.file,
                },
              ).toJson());
        }
      }

      final pinCorrect = await checkPin(
        pin: state.webSendState!.pin,
        pinAttempts: state.webSendState!.pinAttempts,
        request: request,
      );
      if (!pinCorrect) {
        return;
      }

      final streamController = StreamController<bool>();
      final sessionId = request.ip;
      gateway.setState(
        (oldState) => oldState!.copyWith(
          webSendState: oldState.webSendState!.copyWith(
            sessions: {
              ...oldState.webSendState!.sessions,
              sessionId: WebSendSession(
                sessionId: sessionId,
                responseHandler: streamController,
                ip: request.ip,
                deviceInfo: request.deviceInfo,
              ),
            },
          ),
        ),
      );

      final accepted = state.webSendState?.autoAccept == true || await streamController.stream.first;
      if (!accepted) {
        // user rejected the file transfer
        gateway.setState(
          (oldState) => oldState!.copyWith(
            webSendState: oldState.webSendState!.copyWith(
              sessions: {
                for (final entry in oldState.webSendState!.sessions.entries)
                  if (entry.key != sessionId) entry.key: entry.value, // remove session
              },
            ),
          ),
        );
        return await request.respondJson(403, message: 'File transfer rejected.');
      }

      gateway.setState(
        (oldState) => oldState!.copyWith(
          webSendState: oldState.webSendState!.updateSession(
            sessionId: sessionId,
            update: (oldSession) {
              return oldSession.copyWith(
                responseHandler: null, // this indicates that the session is active
              );
            },
          ),
        ),
      );
      final deviceInfo = gateway.ref.read(deviceInfoProvider);
      return await request.respondJson(200,
          body: ReceiveRequestResponseDto(
            info: InfoDto(
              alias: alias,
              version: protocolVersion,
              deviceModel: deviceInfo.deviceModel,
              deviceType: deviceInfo.deviceType,
              fingerprint: fingerprint,
              download: true,
            ),
            sessionId: sessionId,
            files: {
              for (final entry in state.webSendState!.files.entries) entry.key: entry.value.file,
            },
          ).toJson());
    });

    router.get(ApiRoute.download.v2, (HttpRequest request) async {
      final sessionId = request.uri.queryParameters['sessionId'];
      if (sessionId == null) {
        return await request.respondJson(400, message: 'Missing sessionId.');
      }

      final webSendState = _authorizedWebSendState(request, sessionId);
      if (webSendState == null) {
        return await request.respondJson(403, message: 'Invalid sessionId.');
      }

      final fileId = request.uri.queryParameters['fileId'];
      if (fileId == null) {
        return await request.respondJson(400, message: 'Missing fileId.');
      }

      final file = webSendState.files[fileId];
      if (file == null) {
        return await request.respondJson(403, message: 'Invalid fileId.');
      }

      final fileName = file.file.fileName.split('/').last;
      final _WebDownloadSource source;
      try {
        source = await _createDownloadSource(file);
      } catch (_) {
        return await request.respondJson(500, message: 'Could not read file.');
      }

      final response = request.response;
      response.headers
        ..set(HttpHeaders.contentTypeHeader, 'application/octet-stream')
        ..set(
          'content-disposition',
          'attachment; filename="${Uri.encodeComponent(fileName)}"',
        )
        ..set(
          HttpHeaders.acceptRangesHeader,
          source.supportsRanges ? 'bytes' : 'none',
        );

      HttpByteRange? range;
      if (source.supportsRanges) {
        final rangeValues = request.headers[HttpHeaders.rangeHeader];
        final rangeHeader = rangeValues?.join(',');
        try {
          range = HttpByteRange.parse(
            rangeHeader,
            resourceLength: source.length!,
          );
        } on MalformedHttpByteRangeException {
          // RFC 9110 allows a server to ignore a malformed or unsupported
          // Range header and return the complete representation.
          range = null;
        } on UnsatisfiableHttpByteRangeException {
          response
            ..statusCode = HttpStatus.requestedRangeNotSatisfiable
            ..headers.set(
              HttpHeaders.contentRangeHeader,
              'bytes */${source.length}',
            )
            ..headers.set(HttpHeaders.contentLengthHeader, '0');
          return await response.close();
        }
      }

      if (range == null) {
        response.statusCode = HttpStatus.ok;
        if (source.length != null) {
          response.headers.set(
            HttpHeaders.contentLengthHeader,
            '${source.length}',
          );
        }
      } else {
        response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes ${range.start}-${range.end}/${source.length}',
          )
          ..headers.set(
            HttpHeaders.contentLengthHeader,
            '${range.contentLength}',
          );
      }

      await _sendTask(request, source.open(range), name: file.file.fileName, size: range?.contentLength ?? source.length ?? file.file.size);
    });

    router.get(_downloadAllRoute, (HttpRequest request) async {
      final sessionId = request.uri.queryParameters['sessionId'];
      if (sessionId == null) {
        return await request.respondJson(400, message: 'Missing sessionId.');
      }

      final webSendState = _authorizedWebSendState(request, sessionId);
      if (webSendState == null) {
        return await request.respondJson(403, message: 'Invalid sessionId.');
      }

      final List<StreamingZipEntry> archiveEntries;
      try {
        archiveEntries = await _createArchiveEntries(webSendState);
        const StreamingZipWriter().validateEntries(archiveEntries);
      } on _UnknownArchiveSourceSizeException catch (error) {
        return await request.respondJson(422, message: error.message);
      } on StreamingZipException catch (error) {
        return await request.respondJson(
          422,
          message: 'Files cannot be archived: $error',
        );
      } on FormatException catch (error) {
        return await request.respondJson(
          422,
          message: 'Files cannot be archived: ${error.message}',
        );
      } catch (_) {
        return await request.respondJson(
          500,
          message: 'Could not read files for archive.',
        );
      }

      final response = request.response
        ..statusCode = HttpStatus.ok
        ..bufferOutput = false;
      response.headers
        ..set(HttpHeaders.contentTypeHeader, 'application/zip')
        ..set(
          'content-disposition',
          'attachment; filename="$_downloadAllFileName"; '
              "filename*=UTF-8''$_downloadAllFileName",
        )
        ..set(HttpHeaders.acceptRangesHeader, 'none')
        ..set(HttpHeaders.cacheControlHeader, 'no-store');

      await _sendTask(request, const StreamingZipWriter().write(archiveEntries),
          name: _downloadAllFileName, size: archiveEntries.fold<int>(0, (sum, entry) => sum + entry.sizeBytes));
    });
  }

  Future<void> _sendTask(HttpRequest request, Stream<List<int>> bytes, {required String name, required int size}) async {
    final id = _uuid.v4();
    final manager = gateway.ref.notifier(taskProvider);
    _downloadTasks.add(id);
    manager.put(TransferTask(
        id: id,
        kind: TransferTaskKind.send,
        peer: 'Browser ${request.ip}',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        stage: TransferTaskStage.queued,
        files: [
          {'id': 'download', 'name': name, 'size': size, 'status': 'queue'}
        ]));
    StreamSubscription<List<int>>? subscription;
    manager.cancellations[id] = () {
      manager.queue.release(id);
      unawaited(subscription?.cancel());
      unawaited(request.response.close().then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    };
    try {
      if (!await manager.queue.acquire(id)) return;
      manager.update(id, TransferTaskStage.running);
      var sent = 0;
      final (controller, activeSubscription) = bytes.map((chunk) {
        if (manager.state.tasks[id]?.stage == TransferTaskStage.canceled) {
          throw StateError('Task canceled');
        }
        sent += chunk.length;
        gateway.ref.notifier(progressProvider).setProgress(sessionId: id, fileId: 'download', progress: size > 0 ? (sent / size).clamp(0, 1) : 0);
        return chunk;
      }).digested();
      subscription = activeSubscription;
      await request.response.addStream(controller.stream);
      await request.response.close();
      if (manager.state.tasks[id]?.stage != TransferTaskStage.canceled) {
        manager.checkpoint(id, 'download', size);
        manager.update(id, TransferTaskStage.completed);
      }
    } catch (error) {
      if (manager.state.tasks[id]?.stage != TransferTaskStage.canceled) {
        manager.update(id, TransferTaskStage.failed, error: error.toString());
      }
    } finally {
      await subscription?.cancel();
      manager.queue.release(id);
      _downloadTasks.remove(id);
      manager.cancellations.remove(id);
    }
  }

  void cancelDownloads() {
    if (_downloadTasks.isEmpty) return;
    final manager = gateway.ref.notifier(taskProvider);
    for (final id in _downloadTasks.toList()) {
      manager.cancel(id);
    }
  }

  WebSendState? _authorizedWebSendState(
    HttpRequest request,
    String sessionId,
  ) {
    final webSendState = gateway.getState().webSendState;
    final session = webSendState?.sessions[sessionId];
    if (session == null || session.responseHandler != null || session.ip != request.ip) {
      return null;
    }
    return webSendState;
  }

  Future<List<StreamingZipEntry>> _createArchiveEntries(
    WebSendState webSendState,
  ) async {
    validateTaskPaths(webSendState.files.values.map((file) => file.file.fileName));
    final archiveEntries = <StreamingZipEntry>[];
    for (final stateEntry in webSendState.files.entries) {
      final webFile = stateEntry.value;
      final source = await _createDownloadSource(webFile);
      final sizeBytes = source.length ?? webFile.file.size;
      if (sizeBytes < 0) {
        throw _UnknownArchiveSourceSizeException(webFile.file.fileName);
      }
      archiveEntries.add(
        StreamingZipEntry(
          name: webFile.file.fileName,
          sizeBytes: sizeBytes,
          modifiedTime: webFile.file.metadata?.lastModified,
          open: () => source.open(null),
        ),
      );
    }
    return archiveEntries;
  }

  Future<_WebDownloadSource> _createDownloadSource(WebSendFile file) async {
    final bytes = file.bytes;
    if (bytes != null) {
      return _WebDownloadSource(
        length: bytes.length,
        supportsRanges: true,
        open: (range) => Stream.value(
          range == null ? bytes : bytes.sublist(range.start, range.end + 1),
        ),
      );
    }

    final path = file.path;
    if (path == null) {
      throw StateError('A web send file must contain bytes or a path.');
    }

    if (path.startsWith('content://')) {
      final uri = Uri.parse(path);
      final reportedLength = await _uriContent.getContentLength(uri);
      final length = reportedLength != null && reportedLength >= 0 ? reportedLength : null;
      return _WebDownloadSource(
        length: length,
        supportsRanges: length != null,
        open: (range) {
          final stream = _uriContent.getContentStream(uri);
          if (length == null) {
            return stream;
          }

          return sliceByteStream(
            stream,
            start: range?.start ?? 0,
            length: range?.contentLength ?? length,
          );
        },
      );
    }

    final diskFile = File(path);
    final length = await diskFile.length();
    return _WebDownloadSource(
      length: length,
      supportsRanges: true,
      open: (range) => diskFile.openRead(
        range?.start,
        range == null ? null : range.end + 1,
      ),
    );
  }

  Future<void> initializeWebSend({required List<CrossFile> files}) async {
    final webSendState = WebSendState(
      sessions: {},
      files: Map.fromEntries(await Future.wait(files.map((file) async {
        final id = _uuid.v4();
        return MapEntry(
          id,
          WebSendFile(
            file: FileDto(
              id: id,
              fileName: file.name,
              size: file.size,
              fileType: file.fileType,
              hash: null,
              preview: files.first.fileType == FileType.text && files.first.bytes != null
                  ? utf8.decode(files.first.bytes!) // send simple message by embedding it into the preview
                  : null,
              metadata: file.lastModified != null || file.lastAccessed != null
                  ? FileMetadata(
                      lastModified: file.lastModified,
                      lastAccessed: file.lastAccessed,
                    )
                  : null,
              legacy: false,
            ),
            asset: file.asset,
            path: file.path,
            bytes: file.bytes,
          ),
        );
      }))),
      autoAccept: gateway.ref.read(settingsProvider).shareViaLinkAutoAccept,
      pin: null,
      pinAttempts: {},
    );

    gateway.setState(
      (oldState) => oldState?.copyWith(
        webSendState: webSendState,
      ),
    );
  }

  void acceptRequest(String sessionId) {
    _respondRequest(sessionId, true);
  }

  void declineRequest(String sessionId) {
    _respondRequest(sessionId, false);
  }

  void _respondRequest(String sessionId, bool accepted) {
    final controller = gateway.getState().webSendState?.sessions[sessionId]?.responseHandler;
    if (controller == null) {
      return;
    }

    controller.add(accepted);
    controller.close(); // ignore: discarded_futures
  }
}

class _WebDownloadSource {
  const _WebDownloadSource({
    required this.length,
    required this.supportsRanges,
    required this.open,
  });

  final int? length;
  final bool supportsRanges;
  final Stream<List<int>> Function(HttpByteRange? range) open;
}

class _UnknownArchiveSourceSizeException implements Exception {
  const _UnknownArchiveSourceSizeException(this.fileName);

  final String fileName;

  String get message => 'Cannot archive "$fileName" because its size is unknown.';
}

extension on WebSendState {
  WebSendState updateSession({
    required String sessionId,
    required WebSendSession Function(WebSendSession oldSession) update,
  }) {
    return copyWith(
      sessions: {...sessions}..update(
          sessionId,
          (session) => update(session),
        ),
    );
  }
}
