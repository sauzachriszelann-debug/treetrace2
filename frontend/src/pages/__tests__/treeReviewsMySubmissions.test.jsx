// @vitest-environment jsdom
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { MemoryRouter } from "react-router-dom";
import TreeReviews from "@/pages/TreeReviews";
import Sidebar from "@/components/layout/Sidebar";
import { treeSubmissionsApi } from "@/api/treeSubmissions";

const auth = vi.hoisted(() => ({ user: { role: "admin", id: 1 }, isLoadingAuth: false }));
vi.mock("@/lib/AuthContext", () => ({ useAuth: () => auth }));
vi.mock("@/hooks/useOfflineSync", () => ({ useOfflineSync: () => ({ isOnline: true, queueLength: 0 }) }));
vi.mock("@/api/treeSubmissions", () => ({ treeSubmissionsApi: {
  list: vi.fn(), my: vi.fn(), mySpecies: vi.fn(), deleteMine: vi.fn(),
} }));
vi.mock("@/api/ai", () => ({ aiApi: { listUnknown: async () => [] } }));
vi.mock("sonner", () => ({ toast: { success: vi.fn(), error: vi.fn() } }));
afterEach(cleanup);
beforeEach(() => {
  vi.resetAllMocks();
  auth.user = { role: "admin", id: 1 };
  treeSubmissionsApi.list.mockResolvedValue([]);
  treeSubmissionsApi.my.mockResolvedValue([{ id: 7, common_name: "My mango", status: "pending", dbh_cm: 30 }]);
  treeSubmissionsApi.mySpecies.mockResolvedValue([]);
});
function openReviews() {
  render(<QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
    <MemoryRouter><TreeReviews /></MemoryRouter>
  </QueryClientProvider>);
}
test("own cards open inside Tree Reviews and nested details and delete confirmation remain usable", async () => {
  openReviews();
  expect(treeSubmissionsApi.my).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole("button", { name: "My Submissions" }));
  const popup = await screen.findByRole("dialog", { name: "My Submissions" });
  fireEvent.click(await within(popup).findByRole("button", { name: "View submission: My mango" }));
  const details = await screen.findByRole("dialog", { name: "My mango" });
  expect(within(details).getByText("30 cm")).toBeTruthy();
  fireEvent.click(within(details).getByRole("button", { name: "Close" }));
  const cards = await screen.findByRole("dialog", { name: "My Submissions" });
  fireEvent.click(within(cards).getByRole("button", { name: "Delete submission: My mango" }));
  const confirmation = await screen.findByRole("dialog", { name: "Delete this submission?" });
  fireEvent.click(within(confirmation).getByRole("button", { name: "Cancel" }));
  expect(treeSubmissionsApi.deleteMine).not.toHaveBeenCalled();
  fireEvent.click(within(await screen.findByRole("dialog", { name: "My Submissions" })).getByRole("button", { name: "Close" }));
  expect(screen.getByRole("heading", { name: "Tree Reviews" })).toBeTruthy();
  expect(screen.queryByRole("dialog")).toBeNull();
});
test("field workers can open their own submissions from reviews", async () => {
  auth.user = { role: "field_worker", id: 2 };
  openReviews();
  fireEvent.click(screen.getByRole("button", { name: "My Submissions" }));
  expect(await screen.findByRole("button", { name: "View submission: My mango" })).toBeTruthy();
});
test.each(["admin", "field_worker"])("%s uses the review button rather than a duplicate sidebar item", (role) => {
  render(<MemoryRouter><Sidebar user={{ role }} /></MemoryRouter>);
  expect(screen.queryByRole("link", { name: "My Submissions" })).toBeNull();
  expect(screen.getByRole("link", { name: "Tree Reviews" })).toBeTruthy();
});
test("citizens keep their standalone My Submissions navigation", () => {
  render(<MemoryRouter><Sidebar user={{ role: "citizen" }} /></MemoryRouter>);
  expect(screen.getByRole("link", { name: "My Submissions" })).toBeTruthy();
});
test("citizen access to Tree Reviews stays blocked", () => {
  auth.user = { role: "citizen", id: 3 };
  openReviews();
  expect(screen.getByText("Staff access required")).toBeTruthy();
  expect(screen.queryByRole("button", { name: "My Submissions" })).toBeNull();
});
