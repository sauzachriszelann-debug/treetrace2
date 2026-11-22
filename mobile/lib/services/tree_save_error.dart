import 'package:dio/dio.dart';

String treeSaveErrorMessage(DioException error) {
  final status = error.response?.statusCode;
  if (status == 401) return 'Your session expired. Sign in again. Your pending submission is kept.';
  if (status == 403) return 'You do not have permission to save this tree. Your pending submission is kept.';
  if (status == 422 || status == 400) {
    final data = error.response?.data;
    final detail = data is Map ? data['detail'] : null;
    final validation = detail is List ? detail.whereType<Map>().take(3).map((item) {
      final path = item['loc'];
      final field = path is List ? path.where((part) => part != 'body').join('.') : 'Tree details';
      return '$field: ${item['msg'] ?? 'Invalid value'}';
    }).join('; ') : null;
    final reason = detail is String ? detail
        : validation != null && validation.isNotEmpty ? validation
        : 'Some tree details were rejected. Check the form.';
    return '$reason Your pending submission is kept.';
  }
  if (status != null && status >= 500) {
    return 'The server could not finish saving (HTTP $status). Your pending submission is kept; retry with the same submission.';
  }
  if (status != null) return 'Save failed (HTTP $status). Your pending submission is kept.';
  return 'Could not reach the server or the request timed out. Your pending submission is kept on this device. Check the backend and phone connection before retrying.';
}
