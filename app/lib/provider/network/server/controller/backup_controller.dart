import 'dart:io';

import 'package:localsend_app/features/backup/protocol/protocol.dart';
import 'package:localsend_app/features/backup/receiver/backup_receipt_coordinator.dart';
import 'package:localsend_app/features/backup/receiver/backup_receipt_store.dart';
import 'package:localsend_app/util/simple_server.dart';
import 'package:logging/logging.dart';

final _logger = Logger('BackupController');

/// LocalShare-only endpoints for durable native backup acknowledgements.
///
/// File approval and streaming continue to use LocalSend's normal
/// prepare-upload/upload routes. These endpoints plan around already committed
/// items and recover a receipt when the final response was lost.
final class BackupController {
  BackupController(
    this.coordinator, {
    BackupProtocolCodec codec = const BackupProtocolCodec(),
  }) : _codec = codec;

  final BackupReceiptCoordinator coordinator;
  final BackupProtocolCodec _codec;

  void installRoutes({
    required SimpleServerRouteBuilder router,
    required String fingerprint,
  }) {
    router.post(BackupProtocolRoutes.plan, (request) async {
      await _handlePlan(request, fingerprint);
    });
    router.post(BackupProtocolRoutes.commit, (request) async {
      await _handleCommit(request, fingerprint);
    });
    router.post(BackupProtocolRoutes.receipt, (request) async {
      await _handleReceipt(request, fingerprint);
    });
    router.post(BackupProtocolRoutes.cancel, (request) async {
      await _handleCancel(request, fingerprint);
    });
  }

  Future<void> _handlePlan(HttpRequest request, String fingerprint) async {
    try {
      final decoded = _codec.decodePlanRequest(await request.readAsString());
      if (!_targetMatches(decoded.metadata.targetFingerprint, fingerprint)) {
        return await request.respondJson(
          HttpStatus.preconditionFailed,
          message: 'Backup target fingerprint mismatch.',
        );
      }
      final response = await coordinator.plan(decoded.metadata);
      return await request.respondJson(
        HttpStatus.ok,
        body: Map<String, dynamic>.from(
          _codec.planResponseToJson(response),
        ),
      );
    } catch (error, stackTrace) {
      return _respondFailure(request, error, stackTrace);
    }
  }

  Future<void> _handleCommit(HttpRequest request, String fingerprint) async {
    try {
      final decoded = _codec.decodeCommitRequest(await request.readAsString());
      if (!_targetMatches(decoded.metadata.targetFingerprint, fingerprint)) {
        return await request.respondJson(
          HttpStatus.preconditionFailed,
          message: 'Backup target fingerprint mismatch.',
        );
      }
      final response = await coordinator.commit(decoded.metadata);
      return await request.respondJson(
        HttpStatus.ok,
        body: Map<String, dynamic>.from(
          _codec.commitResponseToJson(response),
        ),
      );
    } catch (error, stackTrace) {
      return _respondFailure(request, error, stackTrace);
    }
  }

  Future<void> _handleReceipt(HttpRequest request, String fingerprint) async {
    try {
      final decoded = _codec.decodeReceiptRequest(await request.readAsString());
      if (!_targetMatches(decoded.metadata.targetFingerprint, fingerprint)) {
        return await request.respondJson(
          HttpStatus.preconditionFailed,
          message: 'Backup target fingerprint mismatch.',
        );
      }
      final response = await coordinator.receipt(decoded.metadata);
      return await request.respondJson(
        HttpStatus.ok,
        body: Map<String, dynamic>.from(
          _codec.receiptResponseToJson(response),
        ),
      );
    } catch (error, stackTrace) {
      return _respondFailure(request, error, stackTrace);
    }
  }

  Future<void> _handleCancel(HttpRequest request, String fingerprint) async {
    try {
      final decoded = _codec.decodeCancelRequest(await request.readAsString());
      if (!_targetMatches(decoded.reference.targetFingerprint, fingerprint)) {
        return await request.respondJson(
          HttpStatus.preconditionFailed,
          message: 'Backup target fingerprint mismatch.',
        );
      }
      final response = await coordinator.cancel(decoded.reference);
      return await request.respondJson(
        HttpStatus.ok,
        body: Map<String, dynamic>.from(
          _codec.cancelResponseToJson(response),
        ),
      );
    } catch (error, stackTrace) {
      return _respondFailure(request, error, stackTrace);
    }
  }
}

bool _targetMatches(String requested, String actual) => requested == actual;

Future<void> _respondFailure(
  HttpRequest request,
  Object error,
  StackTrace stackTrace,
) async {
  final status = switch (error) {
    FormatException() || ArgumentError() => HttpStatus.badRequest,
    BackupReceiptConflict() => HttpStatus.conflict,
    BackupReceiptStateException() ||
    BackupReceiptVerificationException() =>
      HttpStatus.unprocessableEntity,
    _ => HttpStatus.internalServerError,
  };
  if (status >= HttpStatus.internalServerError) {
    _logger.severe('Backup protocol request failed.', error, stackTrace);
  } else {
    _logger.warning('Rejected backup protocol request: $error');
  }
  return request.respondJson(status, message: error.toString());
}
