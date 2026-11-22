// @vitest-environment jsdom
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import MySubmissions from "@/pages/MySubmissions";
import { treeSubmissionsApi } from "@/api/treeSubmissions";

vi.mock("@/api/treeSubmissions", () => ({ treeSubmissionsApi: {
  my: vi.fn(), mySpecies: vi.fn(), deleteMine: vi.fn(),
} }));
vi.mock("sonner", () => ({ toast: { success: vi.fn(), error: vi.fn() } }));
afterEach(cleanup);
beforeEach(() => {
  vi.resetAllMocks();
  treeSubmissionsApi.my.mockResolvedValue([]);
  treeSubmissionsApi.mySpecies.mockResolvedValue([]);
  treeSubmissionsApi.deleteMine.mockResolvedValue(undefined);
});
function openPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(<QueryClientProvider client={client}><MemoryRouter initialEntries={["/my-submissions"]}>
    <Routes><Route path="/my-submissions" element={<MySubmissions />} />
      <Route path="/trees/71" element={<p>Opened tree 71</p>} />
      <Route path="/ai-identify" element={<p>Scanner opened</p>} />
    </Routes>
  </MemoryRouter></QueryClientProvider>);
}
test("compact cards reveal review and measurements only in the popup; approved tree still opens", async () => {
  treeSubmissionsApi.my.mockResolvedValue([{ id: 1, common_name: "Mango", scientific_name: "Mangifera indica",
    status: "approved", approved_tree_id: 71, dbh_cm: 30, height_m: 10, notes: "Near the gate", created_at: "2026-11-18T09:00:00Z" }]);
  openPage();
  const card = await screen.findByRole("button", { name: "View submission: Mango" });
  expect(screen.queryByText("Near the gate")).toBeNull();
  expect(screen.queryByRole("button", { name: /Open Tree/ })).toBeNull();
  fireEvent.click(card);
  const dialog = await screen.findByRole("dialog");
  expect(within(dialog).getByText("30 cm")).toBeTruthy();
  expect(within(dialog).getByText("Near the gate")).toBeTruthy();
  fireEvent.click(within(dialog).getByRole("button", { name: /Open Tree/ }));
  expect(await screen.findByText("Opened tree 71")).toBeTruthy();
});
test("species submission deletion still requires confirmation and calls its own endpoint", async () => {
  treeSubmissionsApi.mySpecies.mockResolvedValue([{ id: 1, identified_as: "Mahogany", review_status: "pending" }]);
  openPage();
  fireEvent.click(await screen.findByRole("button", { name: "View submission: Mahogany" }));
  fireEvent.click(within(await screen.findByRole("dialog")).getByRole("button", { name: "Delete submission" }));
  expect(treeSubmissionsApi.deleteMine).not.toHaveBeenCalled();
  const confirmation = await screen.findByRole("dialog");
  expect(within(confirmation).getByText("Delete this submission?")).toBeTruthy();
  fireEvent.click(within(confirmation).getByRole("button", { name: "Delete submission" }));
  await waitFor(() => expect(treeSubmissionsApi.deleteMine).toHaveBeenCalledWith(1, true));
});
test("rejected submissions retain correction prefill from their detail popup", async () => {
  treeSubmissionsApi.my.mockResolvedValue([{ id: 3, common_name: "Narra", status: "rejected", review_reason: "Capture a clearer photo" }]);
  openPage();
  fireEvent.click(await screen.findByRole("button", { name: "View submission: Narra" }));
  const dialog = await screen.findByRole("dialog");
  expect(within(dialog).getByText("Capture a clearer photo")).toBeTruthy();
  fireEvent.click(within(dialog).getByRole("button", { name: /Resubmit with Corrections/ }));
  expect(await screen.findByText("Scanner opened")).toBeTruthy();
  expect(JSON.parse(sessionStorage.getItem("treetrace_submission_prefill")).common_name).toBe("Narra");
});
