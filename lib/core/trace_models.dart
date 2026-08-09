/// Models for publishing claims and tracing media across the public web.
library;

import 'claim_crypto.dart';

enum TraceMedium { image, audio, video, pdf, unknown }

extension TraceMediumX on TraceMedium {
  String get wire => name;

  static TraceMedium parse(String? value) {
    switch (value) {
      case 'image':
        return TraceMedium.image;
      case 'audio':
        return TraceMedium.audio;
      case 'video':
        return TraceMedium.video;
      case 'pdf':
        return TraceMedium.pdf;
      default:
        return TraceMedium.unknown;
    }
  }
}

/// A claim registered so copies found online can be linked to an owner.
class PublishedClaim {
  const PublishedClaim({
    required this.id,
    required this.medium,
    required this.owner,
    required this.subject,
    required this.reference,
    required this.issued,
    required this.publisherId,
    required this.publishedAt,
    this.alg,
    this.kid,
    this.note,
    this.remoteSynced = false,
  });

  final String id;
  final TraceMedium medium;
  final String owner;
  final String subject;

  /// Signature or structural identifier embedded in the media.
  final String reference;
  final String issued;
  final String publisherId;
  final DateTime publishedAt;
  final String? alg;
  final String? kid;
  final String? note;
  final bool remoteSynced;

  Map<String, dynamic> toJson() => {
        'id': id,
        'medium': medium.wire,
        'owner': owner,
        'subject': subject,
        'reference': reference,
        'issued': issued,
        'publisherId': publisherId,
        'publishedAt': publishedAt.toIso8601String(),
        if (alg != null) 'alg': alg,
        if (kid != null) 'kid': kid,
        if (note != null) 'note': note,
        'remoteSynced': remoteSynced,
      };

  static PublishedClaim? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    try {
      return PublishedClaim(
        id: map['id'] as String? ?? '',
        medium: TraceMediumX.parse(map['medium'] as String?),
        owner: map['owner'] as String? ?? '',
        subject: map['subject'] as String? ?? '',
        reference: map['reference'] as String? ?? '',
        issued: map['issued'] as String? ?? '',
        publisherId: map['publisherId'] as String? ?? '',
        publishedAt: DateTime.tryParse(map['publishedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        alg: map['alg'] as String?,
        kid: map['kid'] as String?,
        note: map['note'] as String?,
        remoteSynced: map['remoteSynced'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  PublishedClaim copyWith({bool? remoteSynced, String? note}) => PublishedClaim(
        id: id,
        medium: medium,
        owner: owner,
        subject: subject,
        reference: reference,
        issued: issued,
        publisherId: publisherId,
        publishedAt: publishedAt,
        alg: alg,
        kid: kid,
        note: note ?? this.note,
        remoteSynced: remoteSynced ?? this.remoteSynced,
      );
}

/// A URL the user wants re-scanned for Signata fingerprints.
class WatchTarget {
  const WatchTarget({
    required this.id,
    required this.url,
    required this.addedAt,
    this.label,
    this.lastScannedAt,
    this.lastReference,
  });

  final String id;
  final String url;
  final DateTime addedAt;
  final String? label;
  final DateTime? lastScannedAt;
  final String? lastReference;

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'addedAt': addedAt.toIso8601String(),
        if (label != null) 'label': label,
        if (lastScannedAt != null)
          'lastScannedAt': lastScannedAt!.toIso8601String(),
        if (lastReference != null) 'lastReference': lastReference,
      };

  static WatchTarget? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    try {
      return WatchTarget(
        id: map['id'] as String? ?? '',
        url: map['url'] as String? ?? '',
        addedAt: DateTime.tryParse(map['addedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        label: map['label'] as String?,
        lastScannedAt: DateTime.tryParse(map['lastScannedAt'] as String? ?? ''),
        lastReference: map['lastReference'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  WatchTarget copyWith({
    DateTime? lastScannedAt,
    String? lastReference,
    String? label,
  }) =>
      WatchTarget(
        id: id,
        url: url,
        addedAt: addedAt,
        label: label ?? this.label,
        lastScannedAt: lastScannedAt ?? this.lastScannedAt,
        lastReference: lastReference ?? this.lastReference,
      );
}

/// One online observation of a fingerprinted file.
class TraceSighting {
  const TraceSighting({
    required this.id,
    required this.url,
    required this.medium,
    required this.at,
    required this.found,
    required this.claimStatus,
    this.owner,
    this.subject,
    this.reference,
    this.matchedPublishedClaimId,
    this.contentType,
    this.error,
  });

  final String id;
  final String url;
  final TraceMedium medium;
  final DateTime at;
  final bool found;
  final ClaimStatus claimStatus;
  final String? owner;
  final String? subject;
  final String? reference;
  final String? matchedPublishedClaimId;
  final String? contentType;
  final String? error;

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'medium': medium.wire,
        'at': at.toIso8601String(),
        'found': found,
        'claimStatus': claimStatus.name,
        if (owner != null) 'owner': owner,
        if (subject != null) 'subject': subject,
        if (reference != null) 'reference': reference,
        if (matchedPublishedClaimId != null)
          'matchedPublishedClaimId': matchedPublishedClaimId,
        if (contentType != null) 'contentType': contentType,
        if (error != null) 'error': error,
      };

  static TraceSighting? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    try {
      return TraceSighting(
        id: map['id'] as String? ?? '',
        url: map['url'] as String? ?? '',
        medium: TraceMediumX.parse(map['medium'] as String?),
        at: DateTime.tryParse(map['at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        found: map['found'] as bool? ?? false,
        claimStatus: ClaimStatus.values.firstWhere(
          (s) => s.name == map['claimStatus'],
          orElse: () => ClaimStatus.missing,
        ),
        owner: map['owner'] as String?,
        subject: map['subject'] as String?,
        reference: map['reference'] as String?,
        matchedPublishedClaimId: map['matchedPublishedClaimId'] as String?,
        contentType: map['contentType'] as String?,
        error: map['error'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
