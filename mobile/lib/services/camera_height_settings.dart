import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CameraHeightSettings {
  static const defaultMeters = 1.4;
  static const _key = 'dbh_camera_height_m';
  final FlutterSecureStorage _storage;
  final Future<String?> Function()? reader;
  final Future<void> Function(String)? writer;
  const CameraHeightSettings(
      {FlutterSecureStorage storage = const FlutterSecureStorage(),
      this.reader,
      this.writer})
      : _storage = storage;

  Future<double> read() async {
    final value = double.tryParse(
        await (reader?.call() ?? _storage.read(key: _key)) ?? '');
    return value != null && value.isFinite && value > 0 ? value : defaultMeters;
  }

  Future<void> save(double meters) async {
    if (!meters.isFinite || meters <= 0) {
      throw ArgumentError('Camera height must be positive.');
    }
    if (writer != null) {
      await writer!(meters.toString());
    } else {
      await _storage.write(key: _key, value: meters.toString());
    }
  }
}
