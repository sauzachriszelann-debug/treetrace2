import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Local capture evidence, bound to the ORIGINAL bytes, never a file name.
/// No photos, credentials, GPS or calculated measurements are stored here.
/// Geometry assumes flat ground, correct camera height, a round trunk and a
/// visible trunk/soil contact. EXIF must remain intact. Not field validated.
class PhotoCaptureMetadata {
  final double pitchDegrees, cameraHeightMeters;
  final double? focalPixels;
  const PhotoCaptureMetadata(
      {required this.pitchDegrees,
      required this.cameraHeightMeters,
      this.focalPixels});

  Map<String, dynamic> toJson() => {
        'version': 1,
        'pitch': pitchDegrees,
        'camera_height': cameraHeightMeters,
        'f_px': focalPixels
      };

  static PhotoCaptureMetadata? fromJson(Object? raw) {
    if (raw is! Map || raw['version'] != 1) return null;
    final pitch = raw['pitch'],
        height = raw['camera_height'],
        focal = raw['f_px'];
    if (pitch is! num ||
        !pitch.isFinite ||
        pitch.abs() > 5 ||
        height is! num ||
        !height.isFinite ||
        height <= 0 ||
        (focal != null && (focal is! num || !focal.isFinite || focal <= 0))) {
      return null;
    }
    return PhotoCaptureMetadata(
        pitchDegrees: pitch.toDouble(),
        cameraHeightMeters: height.toDouble(),
        focalPixels: (focal as num?)?.toDouble());
  }
}

class PhotoCaptureMetadataStore {
  static const _key = 'tree_photo_capture_evidence_v1';
  final Future<String?> Function()? reader;
  final Future<void> Function(String)? writer;
  final FlutterSecureStorage storage;
  const PhotoCaptureMetadataStore(
      {this.reader, this.writer, this.storage = const FlutterSecureStorage()});

  Future<String> _digest(File photo) async =>
      (await sha256.bind(photo.openRead()).first).toString();

  Future<Map<String, dynamic>> _records() async {
    final raw = await (reader?.call() ?? storage.read(key: _key));
    if (raw == null) return {};
    final value = jsonDecode(raw);
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }

  /// Failed storage is optional: it must never invalidate a live measurement.
  Future<bool> save(File photo, PhotoCaptureMetadata metadata) async {
    if (PhotoCaptureMetadata.fromJson(metadata.toJson()) == null) return false;
    try {
      final hash = await _digest(photo);
      Map<String, dynamic> records;
      try {
        records = await _records();
      } catch (_) {
        records = {};
      }
      records.remove(hash);
      records[hash] = metadata.toJson();
      while (records.length > 200) {
        records.remove(records.keys.first);
      }
      final encoded = jsonEncode(records);
      if (writer != null) {
        await writer!(encoded);
      } else {
        await storage.write(key: _key, value: encoded);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Renamed exact copies match; crops, edits and recompressions do not.
  Future<PhotoCaptureMetadata?> read(File photo) async {
    try {
      return PhotoCaptureMetadata.fromJson(
          (await _records())[await _digest(photo)]);
    } catch (_) {
      return null;
    }
  }
}
