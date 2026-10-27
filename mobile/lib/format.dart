// Shared display formatting helpers.
//
// Mirrors frontend/src/lib/format.js (React Phase 10A) so the web app and the
// mobile app read identically for the same stored value.

/// Format a carbon mass given in KILOGRAMS for display.
///
/// Small amounts stay in kilograms; one tonne or more switches to tonnes so
/// the dashboard stat reads naturally. This is a pure display concern — it
/// never touches the stored value or the scientific estimate behind it.
///
///   formatCarbonKg(1.09)   -> '1.09 kg'
///   formatCarbonKg(0.5)    -> '0.5 kg'
///   formatCarbonKg(999.99) -> '999.99 kg'
///   formatCarbonKg(1000)   -> '1 t'
///   formatCarbonKg(25400)  -> '25.4 t'
///   formatCarbonKg(0)      -> '0 kg'
///
/// Below one tonne we keep up to two decimals but trim trailing zeros so
/// small values are not padded ('0.5 kg', not '0.50 kg'). At or above one
/// tonne we show one decimal and drop a redundant '.0'.
String formatCarbonKg(double? kg) {
  if (kg == null || !kg.isFinite) return '—';
  if (kg >= 1000) {
    final text = (kg / 1000).toStringAsFixed(1);
    return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text} t';
  }
  final trimmed = kg.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return '${trimmed.isEmpty ? '0' : trimmed} kg';
}
