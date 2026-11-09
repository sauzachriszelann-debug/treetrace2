import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treetrace_mobile/services/ar_tree_height.dart';
import 'package:treetrace_mobile/services/dbh_ar_service.dart';

Map<String, dynamic> observation() => {
  'source': 'arcore_base_anchor', 'tracking': 'tracking', 'stable': true,
  'horizontal_distance_m': 10.0, 'elevation_degrees': 45.0,
  'camera_height_m': 1.5, 'alignment_degrees': 0.0,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('height uses metric anchor distance plus camera height, not a fixed distance', () {
    expect(heightFromArObservation(observation()), closeTo(11.5, 1e-8));
    expect(heightFromArObservation(observation()..['horizontal_distance_m'] = 4), closeTo(5.5, 1e-8));
  });

  test('missing scale, poor alignment and unstable tracking never produce height', () {
    for (final entry in <MapEntry<String, dynamic>>[
      const MapEntry('source', 'ordinary_photo'),
      const MapEntry('tracking', 'paused'), const MapEntry('stable', false),
      const MapEntry('horizontal_distance_m', null),
      const MapEntry('horizontal_distance_m', 0),
      const MapEntry('horizontal_distance_m', 31),
      const MapEntry('elevation_degrees', 80),
      const MapEntry('elevation_degrees', -20),
      const MapEntry('elevation_degrees', double.nan),
      const MapEntry('camera_height_m', 0),
      const MapEntry('alignment_degrees', 10),
    ]) {
      expect(heightFromArObservation(observation()..[entry.key] = entry.value), isNull,
          reason: 'Reject ${entry.key} = ${entry.value}');
    }
  });

  test('unified session flag is sent through native bridge and cancellation preserved', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DbhArService.channel, (call) async {
      received = call;
      return {'status': 'cancelled', 'reason': 'Scan cancelled.'};
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DbhArService.channel, null));
    final result = await DbhArService().scan(unified: true);
    expect(received?.method, 'scan');
    expect(received?.arguments, {'unified': true});
    expect(result['status'], 'cancelled');
    expect(result['image_base64'], isNull);
  });
}
