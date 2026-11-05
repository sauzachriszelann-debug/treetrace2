export function calculateTreeHeightMeters({
  horizontalDistanceMeters,
  topAngleDegrees,
  baseAngleDegrees,
}) {
  const hasValue = (value) =>
    value !== null && value !== undefined && String(value).trim() !== "";
  if (
    !hasValue(horizontalDistanceMeters) ||
    !hasValue(topAngleDegrees) ||
    !hasValue(baseAngleDegrees)
  ) {
    throw new Error("Enter distance and both sight angles.");
  }

  const distance = Number(horizontalDistanceMeters);
  const topAngle = Number(topAngleDegrees);
  const baseAngle = Number(baseAngleDegrees);

  if (!Number.isFinite(distance) || distance <= 0) {
    throw new Error("Enter a finite horizontal distance greater than zero.");
  }
  if (!Number.isFinite(topAngle) || !Number.isFinite(baseAngle)) {
    throw new Error("Enter finite top and base angles.");
  }
  if (Math.abs(topAngle) >= 89 || Math.abs(baseAngle) >= 89) {
    throw new Error("Angles must be between -89° and 89°. Reposition and measure again.");
  }

  const degreesToRadians = (degrees) => (degrees * Math.PI) / 180;
  const height =
    distance *
    (Math.tan(degreesToRadians(topAngle)) -
      Math.tan(degreesToRadians(baseAngle)));
  if (!Number.isFinite(height) || height <= 0) {
    throw new Error(
      "The top angle must be above the base angle. Check the readings and try again.",
    );
  }
  return height;
}
