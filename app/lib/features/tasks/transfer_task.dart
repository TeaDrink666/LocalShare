enum TransferTaskKind { send, receive, backup }

enum TransferTaskStage { queued, waiting, running, verifying, paused, interrupted, completed, failed, canceled }

class TransferTask {
  const TransferTask({
    required this.id,
    required this.kind,
    required this.peer,
    required this.createdAt,
    required this.stage,
    required this.files,
    this.startedAt,
    this.endedAt,
    this.directory,
    this.error,
    this.retryData = const {},
  });
  final String id;
  final TransferTaskKind kind;
  final String peer;
  final int createdAt;
  final TransferTaskStage stage;
  final List<Map<String, dynamic>> files;
  final int? startedAt;
  final int? endedAt;
  final String? directory;
  final String? error;
  final Map<String, dynamic> retryData;

  bool get terminal =>
      {TransferTaskStage.completed, TransferTaskStage.failed, TransferTaskStage.canceled, TransferTaskStage.interrupted}.contains(stage);
  bool get autoClearable => stage == TransferTaskStage.completed || stage == TransferTaskStage.canceled;
  int get totalBytes => files.fold(0, (sum, file) => sum + (file['size'] as int));

  TransferTask copyWith(
          {TransferTaskStage? stage,
          List<Map<String, dynamic>>? files,
          int? startedAt,
          int? endedAt,
          String? directory,
          String? error,
          Map<String, dynamic>? retryData}) =>
      TransferTask(
        id: id,
        kind: kind,
        peer: peer,
        createdAt: createdAt,
        stage: stage ?? this.stage,
        files: files ?? this.files,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt ?? this.endedAt,
        directory: directory ?? this.directory,
        error: error,
        retryData: retryData ?? this.retryData,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'peer': peer,
        'createdAt': createdAt,
        'stage': stage.name,
        'files': files,
        'startedAt': startedAt,
        'endedAt': endedAt,
        'directory': directory,
        'error': error,
        'retryData': retryData
      };

  factory TransferTask.fromJson(Map<String, dynamic> json) => TransferTask(
        id: json['id'] as String,
        kind: TransferTaskKind.values.byName(json['kind'] as String),
        peer: json['peer'] as String,
        createdAt: json['createdAt'] as int,
        stage: TransferTaskStage.values.byName(json['stage'] as String),
        files: (json['files'] as List).map((f) => Map<String, dynamic>.from(f as Map)).toList(),
        startedAt: json['startedAt'] as int?,
        endedAt: json['endedAt'] as int?,
        directory: json['directory'] as String?,
        error: json['error'] as String?,
        retryData: Map<String, dynamic>.from((json['retryData'] as Map?) ?? {}),
      );
}
