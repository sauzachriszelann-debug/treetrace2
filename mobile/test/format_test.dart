import 'package:flutter_test/flutter_test.dart';
import 'package:treetrace_mobile/format.dart';

// Mirrors the web suite (frontend/src/lib/__tests__/format.test.js) so both
// clients must agree on how a stored carbon mass is DISPLAYED.
void main() {
  group('formatCarbonKg', () {
    test('keeps amounts below one tonne in kilograms', () {
      expect(formatCarbonKg(1.09), '1.09 kg');
      expect(formatCarbonKg(0.5), '0.5 kg');
      expect(formatCarbonKg(2.32), '2.32 kg');
      expect(formatCarbonKg(12.34), '12.34 kg');
      expect(formatCarbonKg(999.99), '999.99 kg');
    });

    test('never pads a small value with fake precision', () {
      expect(formatCarbonKg(0), '0 kg');
      expect(formatCarbonKg(10), '10 kg');
      expect(formatCarbonKg(100), '100 kg');
      expect(formatCarbonKg(12), '12 kg');
      for (final kg in <double>[0, 0.5, 1.09, 2.32, 12.34, 999.99]) {
        expect(formatCarbonKg(kg), isNot(contains('0.00')));
      }
    });

    test('switches to tonnes at one tonne and above', () {
      expect(formatCarbonKg(1000), '1 t');
      expect(formatCarbonKg(1090), '1.1 t');
      expect(formatCarbonKg(12340), '12.3 t');
      expect(formatCarbonKg(25400), '25.4 t');
    });

    test('the 999.99 -> 1000 boundary really flips the unit', () {
      expect(formatCarbonKg(999.99), endsWith('kg'));
      expect(formatCarbonKg(1000), endsWith('t'));
    });

    test('guards missing or unusable values', () {
      expect(formatCarbonKg(null), '—');
      expect(formatCarbonKg(double.nan), '—');
      expect(formatCarbonKg(double.infinity), '—');
    });
  });
}
