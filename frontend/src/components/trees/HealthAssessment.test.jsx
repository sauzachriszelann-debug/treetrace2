import { fireEvent, render, screen, cleanup } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import HealthBadge from "./HealthBadge";
import HealthLogForm from "./HealthLogForm";

afterEach(cleanup);

test("missing health is displayed neutrally, never as healthy", () => {
  render(<HealthBadge />);
  const badge = screen.getByText("Not assessed");
  expect(badge.className).toContain("bg-slate-100");
  expect(screen.queryByText("Healthy")).toBeNull();
});

test("an assessment form does not preselect healthy", () => {
  const submit = vi.fn();
  render(<HealthLogForm onSubmit={submit} onCancel={() => {}} />);
  expect(screen.getByRole("combobox").textContent).toContain("Not assessed");
  fireEvent.click(screen.getByRole("button", { name: "Save Assessment" }));
  expect(submit).toHaveBeenCalledWith(expect.objectContaining({ condition: "Not assessed" }));
});

test("an existing assessment label remains unchanged", () => {
  render(<HealthBadge status="Poor" />);
  expect(screen.getByText("Poor").className).toContain("bg-red-100");
});
