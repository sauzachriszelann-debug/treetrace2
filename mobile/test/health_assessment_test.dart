import 'package:flutter_test/flutter_test.dart';
import 'package:treetrace_mobile/models/models.dart';
import 'package:treetrace_mobile/services/theme.dart';

void main() {
  test('missing health status stays unassessed rather than healthy', () {
    final tree = TreeModel.fromJson({'id': 1, 'common_name': 'Mango'});
    expect(tree.healthStatus, 'Not assessed');
    expect(tree.toJson()['health_status'], 'Not assessed');
    expect(healthColor(tree.healthStatus), kMutedFg);
  });

  test('existing assessments are retained when reading tree records', () {
    for (final status in ['Healthy', 'Fair', 'Poor', 'Not assessed']) {
      final tree = TreeModel.fromJson(
          {'id': 1, 'common_name': 'Mango', 'health_status': status});
      expect(tree.healthStatus, status);
    }
  });
}
