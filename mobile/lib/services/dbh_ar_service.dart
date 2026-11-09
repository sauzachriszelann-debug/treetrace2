import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native AR owns the camera and returns a synchronized frame/depth bundle.
class DbhArService {
  static const channel = MethodChannel('treetrace/dbh_ar');

  Future<Map<String, dynamic>> capabilities() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return {
        'supported': false,
        'reason':
            'Automatic depth scanning is currently available in the Android build. '
                'iPhone camera integration is not available yet.',
      };
    }
    for (var attempt = 0; attempt < 4; attempt++) {
      final result = Map<String, dynamic>.from(
        await channel.invokeMapMethod<String, dynamic>('capabilities') ?? {},
      );
      if (result['checking'] != true) return result;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return {
      'supported': false,
      'reason': 'Phone support is still being checked. Try again shortly.'
    };
  }

  Future<Map<String, dynamic>> scan({bool unified = false}) async {
    final result = Map<String, dynamic>.from(
      await channel
              .invokeMapMethod<String, dynamic>('scan', {'unified': unified}) ??
          {},
    );
    if (result['path'] is! String) return result;
    final file = File(result['path'] as String);
    try {
      return Map<String, dynamic>.from(
          jsonDecode(await file.readAsString()) as Map);
    } finally {
      if (await file.exists()) await file.delete();
    }
  }
}

/// Never parse null, fallback, nonfinite or out-of-range measurements as success.
double? acceptedAutomaticDbh(Map<String, dynamic> response) {
  final value = response['dbh_cm'];
  if (response['status'] != 'ok' ||
      response['fallback'] == true ||
      response['error'] == true ||
      value is! num ||
      !value.isFinite ||
      value < 3 ||
      value > 300) {
    return null;
  }
  return value.toDouble();
}
