/// A named destination whose confirmed backup history is kept independently.
final class BackupTargetProfile {
  const BackupTargetProfile({
    required this.id,
    required this.displayName,
    required this.createdAtUtc,
    required this.lastConfirmedAtUtc,
    this.deviceFingerprint,
  });

  factory BackupTargetProfile.fromJson(Map<String, Object?> json) {
    const legacyKeys = {
      'id',
      'displayName',
      'createdAtUtc',
      'lastConfirmedAtUtc',
    };
    const currentKeys = {...legacyKeys, 'deviceFingerprint'};
    final actualKeys = json.keys.toSet();
    final hasLegacyShape = actualKeys.length == legacyKeys.length &&
        actualKeys.containsAll(legacyKeys);
    final hasCurrentShape = actualKeys.length == currentKeys.length &&
        actualKeys.containsAll(currentKeys);
    if (!hasLegacyShape && !hasCurrentShape) {
      throw const FormatException('Invalid backup profile fields.');
    }

    final id = json['id'];
    final displayName = json['displayName'];
    final createdAtUtc = _decodeUtc(json['createdAtUtc'], 'createdAtUtc');
    final lastConfirmedValue = json['lastConfirmedAtUtc'];
    final lastConfirmedAtUtc = lastConfirmedValue == null
        ? null
        : _decodeUtc(lastConfirmedValue, 'lastConfirmedAtUtc');
    final deviceFingerprint = json['deviceFingerprint'];
    if (id is! String ||
        displayName is! String ||
        (deviceFingerprint != null && deviceFingerprint is! String)) {
      throw const FormatException('Invalid backup profile values.');
    }

    final profile = BackupTargetProfile(
      id: id,
      displayName: displayName,
      createdAtUtc: createdAtUtc,
      lastConfirmedAtUtc: lastConfirmedAtUtc,
      deviceFingerprint: deviceFingerprint as String?,
    );
    try {
      profile.validate();
    } on ArgumentError catch (error) {
      throw FormatException('Invalid backup profile: ${error.message}');
    }
    return profile;
  }

  final String id;
  final String displayName;
  final DateTime createdAtUtc;
  final DateTime? lastConfirmedAtUtc;
  final String? deviceFingerprint;

  BackupTargetProfile copyWith({
    String? displayName,
    DateTime? lastConfirmedAtUtc,
    String? deviceFingerprint,
  }) {
    return BackupTargetProfile(
      id: id,
      displayName: displayName ?? this.displayName,
      createdAtUtc: createdAtUtc,
      lastConfirmedAtUtc: lastConfirmedAtUtc ?? this.lastConfirmedAtUtc,
      deviceFingerprint: deviceFingerprint ?? this.deviceFingerprint,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'displayName': displayName,
        'createdAtUtc': createdAtUtc.toIso8601String(),
        'lastConfirmedAtUtc': lastConfirmedAtUtc?.toIso8601String(),
        'deviceFingerprint': deviceFingerprint,
      };

  void validate() {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'Invalid backup profile ID.');
    }
    if (displayName.trim().isEmpty ||
        displayName.length > 80 ||
        displayName.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
      throw ArgumentError.value(
        displayName,
        'displayName',
        'Must contain between 1 and 80 visible characters.',
      );
    }
    if (!createdAtUtc.isUtc ||
        (lastConfirmedAtUtc != null && !lastConfirmedAtUtc!.isUtc)) {
      throw ArgumentError('Backup profile timestamps must be UTC.');
    }
    final fingerprint = deviceFingerprint;
    if (fingerprint != null &&
        (fingerprint.trim().isEmpty ||
            fingerprint.length > 256 ||
            fingerprint.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f))) {
      throw ArgumentError.value(
        fingerprint,
        'deviceFingerprint',
        'Must be a non-empty device identifier.',
      );
    }
  }
}

DateTime _decodeUtc(Object? value, String fieldName) {
  if (value is! String || !value.endsWith('Z')) {
    throw FormatException('$fieldName must be a UTC timestamp.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw FormatException('$fieldName must be a UTC timestamp.');
  }
  return parsed;
}
