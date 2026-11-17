const estimateSuffix =
  " from photos; not field-validated. Carbon derived from these dimensions is also approximate.";
const dimensionLabels = { dbh_cm: "DBH", height_m: "height" };

export function splitMeasurementNote(value) {
  const dimensions = new Set();
  const notes = (value ?? "").split("\n").filter((line) => {
    const text = line.trim();
    if (!text.startsWith("AI-estimated ") || !text.endsWith(estimateSuffix)) return true;
    const labels = text.slice("AI-estimated ".length, -estimateSuffix.length).split(" and ");
    const keys = labels.map((label) =>
      Object.keys(dimensionLabels).find((key) => dimensionLabels[key] === label),
    );
    if (keys.some((key) => !key)) return true;
    keys.forEach((key) => dimensions.add(key));
    return false;
  }).join("\n");

  return { notes, dimensions: [...dimensions] };
}

export function formatMeasurementDimensions(dimensions) {
  return dimensions.map((key) => dimensionLabels[key]).join(" and ");
}

export function appendMeasurementNote(notes, dimensions) {
  if (!dimensions.length) return notes;
  return [
    notes,
    `AI-estimated ${formatMeasurementDimensions(dimensions)}${estimateSuffix}`,
  ].filter(Boolean).join("\n");
}
