// Shared display formatting helpers.

// Format a carbon mass given in KILOGRAMS for display.
// Small amounts stay in kilograms; larger amounts switch to tonnes so the
// dashboard stat reads naturally. This is a pure display concern — it never
// touches the stored value or the scientific estimate behind it.
//
//   formatCarbonKg(1.09)    -> "1.09 kg"
//   formatCarbonKg(12.34)   -> "12.3 kg"
//   formatCarbonKg(1000)    -> "1.00 t"
//   formatCarbonKg(25400)   -> "25.4 t"
//   formatCarbonKg(0)       -> "0 kg"
//
// Below one tonne we keep two decimals but trim a trailing zero so small
// values are not padded ("1.09 kg", not "1.09 kg" vs "1.10 kg" noise).
// At or above one tonne we show one decimal in tonnes.
export function formatCarbonKg(kg) {
  // null/undefined/empty mean "no value recorded" — show a dash. (Number(null)
  // is 0 in JS, so these must be filtered before coercion.)
  if (kg === null || kg === undefined || kg === "") return "—";
  const value = Number(kg);
  if (!Number.isFinite(value)) return "—";
  if (value >= 1000) {
    const tonnes = value / 1000;
    // Trim a trailing zero (e.g. "1.0 t" -> "1 t") but keep meaningful digits.
    const text = tonnes.toFixed(1);
    return `${text.replace(/\.0$/, "")} t`;
  }
  // Kilograms: up to 2 decimals, trailing zeros trimmed.
  const text = value.toFixed(2);
  return `${text.replace(/\.?0+$/, "")} kg`;
}
