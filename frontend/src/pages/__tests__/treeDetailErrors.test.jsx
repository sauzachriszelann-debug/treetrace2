import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { afterEach, expect, test, vi } from "vitest";
import TreeDetail from "../TreeDetail";

const state = vi.hoisted(() => ({ error: null, retry: vi.fn() }));
vi.mock("@tanstack/react-query", () => ({
  useQueryClient: () => ({}),
  useQuery: () => ({
    isLoading: false, isError: true, error: state.error, refetch: state.retry,
  }),
}));
vi.mock("@/lib/AuthContext", () => ({ useAuth: () => ({ user: { role: "admin" } }) }));
vi.mock("@/offline/OfflineSyncProvider", () => ({ useOfflineSyncStore: () => ({}) }));

afterEach(() => { cleanup(); vi.clearAllMocks(); });

test("a server failure offers retry without declaring the record missing", () => {
  state.error = { response: { status: 500 } };
  render(<MemoryRouter><TreeDetail /></MemoryRouter>);
  expect(screen.getByRole("alert")).toHaveTextContent("Could not load this tree");
  expect(screen.queryByText("Tree not found.")).toBeNull();
  fireEvent.click(screen.getByRole("button", { name: "Retry" }));
  expect(state.retry).toHaveBeenCalledOnce();
});

test("a genuine missing record shows the missing message", () => {
  state.error = { response: { status: 404 } };
  render(<MemoryRouter><TreeDetail /></MemoryRouter>);
  expect(screen.getByRole("alert")).toHaveTextContent("Tree not found.");
  expect(screen.queryByRole("button", { name: "Retry" })).toBeNull();
});
