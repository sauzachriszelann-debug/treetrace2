import { describe, expect, test } from "vitest";
import { formatCarbonKg } from "../format";

// Phase 10A: carbon display must not collapse small values to zero (the
// dashboard previously rendered 1.09 kg as "0.00 t"). Small amounts stay in
// kilograms; large amounts switch to tonnes.
describe("formatCarbonKg", () => {
  test("the reported bug value: 1.09 kg is not shown as 0.00 t", () => {
    expect(formatCarbonKg(1.09)).toBe("1.09 kg");
  });

  test("small values stay in kilograms with two-decimal precision", () => {
    expect(formatCarbonKg(0.5)).toBe("0.5 kg");
    expect(formatCarbonKg(2.32)).toBe("2.32 kg");
    expect(formatCarbonKg(12.34)).toBe("12.34 kg");
    expect(formatCarbonKg(999.99)).toBe("999.99 kg");
  });

  test("values under 10 kg do not round away to zero", () => {
    for (const kg of [0.01, 0.1, 1, 1.09, 5, 9.99]) {
      expect(formatCarbonKg(kg)).not.toBe("0 kg");
      expect(formatCarbonKg(kg)).not.toContain("0.00");
    }
  });

  test("large values switch to tonnes", () => {
    expect(formatCarbonKg(1000)).toBe("1 t");
    expect(formatCarbonKg(1500)).toBe("1.5 t");
    expect(formatCarbonKg(25400)).toBe("25.4 t");
    expect(formatCarbonKg(1234567)).toBe("1234.6 t");
  });

  test("exactly one tonne is the kilogram/tonne boundary", () => {
    expect(formatCarbonKg(999)).toBe("999 kg");
    expect(formatCarbonKg(1000)).toContain("t");
  });

  test("zero and falsy inputs render sensibly", () => {
    expect(formatCarbonKg(0)).toBe("0 kg");
  });

  test("non-numeric input renders a dash instead of NaN", () => {
    expect(formatCarbonKg(null)).toBe("—");
    expect(formatCarbonKg(undefined)).toBe("—");
    expect(formatCarbonKg("abc")).toBe("—");
    expect(formatCarbonKg(NaN)).toBe("—");
  });

  test("string-numeric input from the API is coerced", () => {
    expect(formatCarbonKg("1.09")).toBe("1.09 kg");
  });
});
