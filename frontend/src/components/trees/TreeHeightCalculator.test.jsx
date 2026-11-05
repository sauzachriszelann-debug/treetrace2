import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, test, vi } from "vitest";
import { MemoryRouter } from "react-router-dom";
import TreeHeightCalculator from "@/components/trees/TreeHeightCalculator";
import TreeForm from "@/components/trees/TreeForm";
import { calculateTreeHeightMeters } from "@/lib/treeHeight";

describe("tree height calculation", () => {
  test("uses signed angles in degrees and returns meters", () => {
    const height = calculateTreeHeightMeters({
      horizontalDistanceMeters: 10,
      topAngleDegrees: 45,
      baseAngleDegrees: -10,
    });

    expect(height).toBeCloseTo(11.7633, 3);
  });

  test.each([
    [0, 45, -10],
    [-1, 45, -10],
    [Number.NaN, 45, -10],
    ["", 45, -10],
    [10, "", -10],
    [10, Number.POSITIVE_INFINITY, -10],
    [10, 89, 0],
    [10, 5, 10],
  ])("rejects invalid distance/angles: %s, %s, %s", (distance, top, base) => {
    expect(() =>
      calculateTreeHeightMeters({
        horizontalDistanceMeters: distance,
        topAngleDegrees: top,
        baseAngleDegrees: base,
      }),
    ).toThrow();
  });
});

function enterExampleAngles() {
  fireEvent.change(screen.getByLabelText("Horizontal distance (m)"), {
    target: { value: "10" },
  });
  fireEvent.change(screen.getByLabelText("Angle to tree top (°)"), {
    target: { value: "45" },
  });
  fireEvent.change(screen.getByLabelText("Angle to tree base (°)"), {
    target: { value: "-10" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Calculate Estimate" }));
}

describe("tree height calculator dialog", () => {
  test("lets the user correct and accept a height estimate", () => {
    const onAccept = vi.fn();
    render(<TreeHeightCalculator onAccept={onAccept} />);

    fireEvent.click(screen.getByRole("button", { name: "Calculate Tree Height" }));
    enterExampleAngles();
    expect(screen.getByText("Estimated Tree Height: 11.76 m")).toBeInTheDocument();

    fireEvent.change(screen.getByLabelText("Correct height if needed (m)"), {
      target: { value: "12.5" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Accept Height" }));

    expect(onAccept).toHaveBeenCalledWith(12.5);
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  });

  test("cancel closes without changing the height", () => {
    const onAccept = vi.fn();
    render(<TreeHeightCalculator onAccept={onAccept} />);

    fireEvent.click(screen.getByRole("button", { name: "Calculate Tree Height" }));
    enterExampleAngles();
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));

    expect(onAccept).not.toHaveBeenCalled();
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  });

  test("accepted estimate fills the existing editable Add Tree height field", () => {
    render(
      <MemoryRouter>
        <TreeForm onSubmit={vi.fn()} />
      </MemoryRouter>,
    );

    fireEvent.click(screen.getByRole("button", { name: "Calculate Tree Height" }));
    enterExampleAngles();
    fireEvent.click(screen.getByRole("button", { name: "Accept Height" }));

    const heightInput = screen.getByLabelText("Height (m)");
    expect(heightInput).toHaveValue(11.76);
    fireEvent.change(heightInput, { target: { value: "12.25" } });
    expect(heightInput).toHaveValue(12.25);
  });
});
