import 'package:dio/dio.dart';

/// Shared, non-sensitive errors. Never display provider bodies, keys or photos.
String identificationError(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status == 401) {
      return 'Your session expired. Sign in again, then retry identification.';
    }
    if (status == 402 || status == 429) {
      return 'Identification limit reached. Try again later or check your plan.';
    }
    if (status == 403) {
      return 'Your account cannot use identification. Check account access.';
    }
    if (status == 413) {
      return 'The photo is too large for this server (HTTP 413). Try a smaller original leaf photo.';
    }
    if (status == 404) {
      return 'Identification is missing on the configured backend (HTTP 404). Check the backend address and deployed version.';
    }
    if (status == 400 || status == 415 || status == 422) {
      return 'The server could not read this image (HTTP $status). Try a JPEG or PNG photo.';
    }
    if (status != null) {
      return 'Identification server error (HTTP $status). Retry; if it continues, check the backend terminal.';
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return 'Identification timed out. Check the backend and try again.';
    }
    return 'Cannot reach the identification backend. Check the phone connection and backend address.';
  }
  if (error is FormatException) {
    return 'The backend returned an invalid identification response. Check the deployed backend version.';
  }
  return 'Could not identify this photo. Retry with a clear leaf photo.';
}
