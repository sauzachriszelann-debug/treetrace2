import 'package:flutter_test/flutter_test.dart';
import 'package:treetrace_mobile/services/botanical_overview.dart';

void main() {
  const fallback =
      'A detailed description of this tree species is not yet available.';

  group('botanicalOverviewDescription', () {
    test('preserves a species description returned by identification', () {
      const description =
          'A tropical evergreen tree with glossy leaves and small flowers.';

      expect(botanicalOverviewDescription(description), description);
    });

    test('uses the neutral fallback when description is missing or blank', () {
      expect(botanicalOverviewDescription(null), fallback);
      expect(botanicalOverviewDescription('  '), fallback);
      expect(botanicalOverviewDescription('null'), fallback);
    });

    test('hides provider and technical fallback messages', () {
      expect(
        botanicalOverviewDescription(
          'Identified using PlantNet. TreeTrace vision enrichment is unavailable.',
        ),
        fallback,
      );
      expect(
        botanicalOverviewDescription('Gemini API error: request failed.'),
        fallback,
      );
    });
  });
}
