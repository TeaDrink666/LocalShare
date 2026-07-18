/// Version of the LocalShare-specific backup extension.
const int backupProtocolVersion = 1;

/// Extension field added to a normal LocalSend prepare-upload request.
///
/// Keeping all LocalShare metadata below one namespaced field lets an
/// unmodified LocalSend request retain its original shape.
const String localShareBackupMetadataField = 'localShareBackup';

/// Stable paths for the LocalShare native backup API.
abstract final class BackupProtocolRoutes {
  static const String base = '/api/localshare/backup/v1';
  static const String plan = '$base/plan';
  static const String commit = '$base/commit';
  static const String receipt = '$base/receipt';
  static const String cancel = '$base/cancel';
}
