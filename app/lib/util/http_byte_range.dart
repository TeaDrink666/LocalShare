/// An inclusive byte range resolved against a resource's current length.
///
/// Use [parse] to resolve a single HTTP `Range` header. A missing header
/// returns `null`, malformed headers throw [MalformedHttpByteRangeException],
/// and syntactically valid ranges that cannot select any bytes throw
/// [UnsatisfiableHttpByteRangeException].
final class HttpByteRange {
  const HttpByteRange._({
    required this.start,
    required this.end,
  });

  /// The zero-based index of the first byte, inclusive.
  final int start;

  /// The zero-based index of the last byte, inclusive.
  final int end;

  /// The number of bytes selected by this range.
  int get contentLength => end - start + 1;

  /// Parses and resolves a single RFC 9110 byte range.
  ///
  /// Supported forms are `bytes=start-end`, `bytes=start-`, and
  /// `bytes=-suffixLength`. Explicit end positions are clamped to the final
  /// byte of the resource, as required by RFC 9110.
  ///
  /// Multiple ranges are deliberately unsupported.
  static HttpByteRange? parse(
    String? header, {
    required int resourceLength,
  }) {
    if (header == null) {
      return null;
    }

    final match = _singleByteRangePattern.firstMatch(header);
    if (match == null || match.start != 0 || match.end != header.length) {
      throw MalformedHttpByteRangeException(
        header: header,
        resourceLength: resourceLength,
        reason: 'Expected exactly one range using the bytes range unit.',
      );
    }

    final startText = match.group(1)!;
    final endText = match.group(2)!;
    if (startText.isEmpty && endText.isEmpty) {
      throw MalformedHttpByteRangeException(
        header: header,
        resourceLength: resourceLength,
        reason: 'A range start or suffix length is required.',
      );
    }

    if (startText.isEmpty) {
      final suffixLength = BigInt.parse(endText);
      if (suffixLength <= BigInt.zero) {
        throw UnsatisfiableHttpByteRangeException(
          header: header,
          resourceLength: resourceLength,
          reason: 'A suffix range must request at least one byte.',
        );
      }
      if (resourceLength <= 0) {
        throw UnsatisfiableHttpByteRangeException(
          header: header,
          resourceLength: resourceLength,
          reason: 'The resource has no selectable bytes.',
        );
      }

      final length = BigInt.from(resourceLength);
      final resolvedStart =
          suffixLength >= length ? BigInt.zero : length - suffixLength;
      return HttpByteRange._(
        start: resolvedStart.toInt(),
        end: resourceLength - 1,
      );
    }

    final start = BigInt.parse(startText);
    final requestedEnd = endText.isEmpty ? null : BigInt.parse(endText);
    if (requestedEnd != null && requestedEnd < start) {
      throw MalformedHttpByteRangeException(
        header: header,
        resourceLength: resourceLength,
        reason: 'The range end cannot precede its start.',
      );
    }
    if (resourceLength <= 0 || start >= BigInt.from(resourceLength)) {
      throw UnsatisfiableHttpByteRangeException(
        header: header,
        resourceLength: resourceLength,
        reason: 'The range starts outside the resource.',
      );
    }

    final lastResourceByte = BigInt.from(resourceLength - 1);
    final resolvedEnd = requestedEnd == null || requestedEnd > lastResourceByte
        ? lastResourceByte
        : requestedEnd;
    return HttpByteRange._(
      start: start.toInt(),
      end: resolvedEnd.toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HttpByteRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() =>
      'HttpByteRange(start: $start, end: $end, contentLength: $contentLength)';
}

final _singleByteRangePattern = RegExp(
  r'^[ \t]*bytes=([0-9]*)-([0-9]*)[ \t]*$',
  caseSensitive: false,
);

/// Base class for failures while parsing or resolving an HTTP byte range.
sealed class HttpByteRangeException implements Exception {
  const HttpByteRangeException({
    required this.header,
    required this.resourceLength,
    required this.reason,
  });

  /// The rejected `Range` header value.
  final String header;

  /// The resource length used while resolving the header.
  final int resourceLength;

  /// A human-readable explanation of the failure.
  final String reason;

  @override
  String toString() =>
      '$runtimeType: $reason (header: "$header", resourceLength: $resourceLength)';
}

/// The header does not use the supported single byte-range grammar.
final class MalformedHttpByteRangeException extends HttpByteRangeException {
  const MalformedHttpByteRangeException({
    required super.header,
    required super.resourceLength,
    required super.reason,
  });
}

/// The header is valid but cannot select bytes from the resource.
final class UnsatisfiableHttpByteRangeException extends HttpByteRangeException {
  const UnsatisfiableHttpByteRangeException({
    required super.header,
    required super.resourceLength,
    required super.reason,
  });
}
