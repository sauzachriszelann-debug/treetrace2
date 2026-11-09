import 'photo_measurement_rules.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// No device-specific focal constant: every measured shot needs its metadata.
class CameraPhotoMetadata {
  static const channel = MethodChannel('treetrace/photo_metadata');

  Future<List<Map<String, dynamic>>> cameras(List<String> ids) async {
    if (defaultTargetPlatform != TargetPlatform.android) return [];
    final result =
        await channel.invokeListMethod<dynamic>('cameras', {'ids': ids});
    return (result ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<Map<String, dynamic>> read(String path, String cameraId) async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // No iOS native implementation/runner is added in this phase. A future
      // iOS build may use original EXIF 35mm focal through the backend only.
      return {'status': 'exif', 'f_px': null};
    }
    if (defaultTargetPlatform != TargetPlatform.android) {
      return {
        'status': 'retake',
        'reason': 'Camera measurements are not supported on this device.'
      };
    }
    final native = Map<String, dynamic>.from(await channel
            .invokeMapMethod<String, dynamic>(
                'read', {'path': path, 'camera_id': cameraId}) ??
        {});
    if (native['status'] != 'ok') return native;
    return focalPixelsFromMetadata(native);
  }
}
