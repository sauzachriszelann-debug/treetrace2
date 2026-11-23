import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treetrace_mobile/services/api_service.dart';

class _Store implements SecureStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<void> delete(String key) async {}
}

class _ReviewApi extends ApiService {
  _ReviewApi({required this.connected, this.failure})
      : super.forTest(storage: _Store());
  final bool connected;
  final Object? failure;
  int uploads = 0;
  int submissions = 0;
  int queued = 0;
  Map<String, dynamic>? sent;
  String? savedPhoto;
  @override
  Future<bool> hasNetworkConnection() async => connected;
  @override
  Future<bool> isOnline() async =>
      throw StateError('Health must not gate review delivery');
  @override
  Future<String> uploadPhotoRequired(File photo,
      {required String purpose}) async {
    uploads++;
    expect(purpose, 'unknown_species');
    return 'https://photos.example/tree.jpg';
  }

  @override
  Future<Map<String, dynamic>> submitUnknownSpecies(
      Map<String, dynamic> data) async {
    submissions++;
    if (failure != null) throw failure!;
    sent = data;
    return {'id': 33};
  }

  @override
  Future<void> queueOfflineAction(String type, Map<String, dynamic> payload,
      {String? photoPath,
      bool requiresReview = false,
      String? reviewReason}) async {
    expect(type, 'SUBMIT_UNKNOWN');
    queued++;
    sent = payload;
    savedPhoto = photoPath;
  }
}

void main() {
  test('connected submission uploads directly without consulting health',
      () async {
    final api = _ReviewApi(connected: true);
    final evidence = {
      'photo_url': '',
      'submitter_notes': 'At the gate',
      'location_description': '7.31, 125.67'
    };
    expect(
        await api.submitUnknownForReview(File('tree.jpg'), evidence), isTrue);
    expect(api.uploads, 1);
    expect(api.submissions, 1);
    expect(api.queued, 0);
    expect(api.sent!['photo_url'], 'https://photos.example/tree.jpg');
    expect(api.sent!['location_description'], evidence['location_description']);
    expect(evidence['photo_url'], '');
  });
  test('no network saves the original photo and evidence for Field Sync',
      () async {
    final api = _ReviewApi(connected: false);
    expect(
        await api.submitUnknownForReview(
            File('tree.jpg'), {'submitter_notes': 'Saved'}),
        isFalse);
    expect(api.uploads, 0);
    expect(api.submissions, 0);
    expect(api.queued, 1);
    expect(api.savedPhoto, 'tree.jpg');
    expect(api.sent!['submitter_notes'], 'Saved');
  });
  test('server rejection stays an error and is not mislabeled offline',
      () async {
    final failure = DioException(
        requestOptions: RequestOptions(path: '/ai/unknown-species'),
        response: Response(
            requestOptions: RequestOptions(path: '/ai/unknown-species'),
            statusCode: 422),
        type: DioExceptionType.badResponse);
    final api = _ReviewApi(connected: true, failure: failure);
    await expectLater(api.submitUnknownForReview(File('tree.jpg'), {}),
        throwsA(same(failure)));
    expect(api.queued, 0);
  });
  test('an ambiguous POST timeout does not create a second offline submission',
      () async {
    final failure = DioException(
        requestOptions: RequestOptions(path: '/ai/unknown-species'),
        type: DioExceptionType.receiveTimeout);
    final api = _ReviewApi(connected: true, failure: failure);
    await expectLater(api.submitUnknownForReview(File('tree.jpg'), {}),
        throwsA(same(failure)));
    expect(api.submissions, 1);
    expect(api.queued, 0);
  });
}
