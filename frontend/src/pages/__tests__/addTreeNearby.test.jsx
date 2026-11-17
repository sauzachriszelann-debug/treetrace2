// @vitest-environment jsdom
import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, expect, test, vi } from "vitest";
import { treesApi } from "@/api/trees";
import AddTree from "@/pages/AddTree";
import { readDraft } from "@/offline/drafts";

vi.mock("@/api/trees", () => ({
  treesApi: {
    nearby: vi.fn(),
    get: vi.fn(),
    create: vi.fn(),
  },
}));
vi.mock("@/api/healthLogs", () => ({
  healthLogsApi: { listByTree: async () => [] },
}));
vi.mock("@/lib/AuthContext", () => ({
  useAuth: () => ({ user: { role: "field_worker" } }),
}));
vi.mock("@/offline/OfflineSyncProvider", () => ({
  useOfflineSyncStore: () => ({ enqueue: vi.fn() }),
}));
vi.mock("@/offline/drafts", () => ({
  readDraft: vi.fn(),
  persistDraft: vi.fn(),
  clearDraft: vi.fn(),
  TREE_DRAFT_SLOT: "tree",
}));
vi.mock("@/components/trees/TreeForm", () => ({
  default: function TestTreeForm({ onSubmit }) {
    return (
      <form
        onSubmit={(event) => {
          event.preventDefault();
          const fields = new FormData(event.currentTarget);
          onSubmit(
            {
              common_name: fields.get("name"),
              lat: fields.get("lat") ? Number(fields.get("lat")) : undefined,
              lng: 125.67,
            },
            { photoFile: fields.get("photo") },
          );
        }}
      >
        <input aria-label="Common Name" name="name" />
        <input aria-label="Latitude" name="lat" defaultValue="7.31" />
        <input aria-label="Tree Photo" name="photo" type="file" />
        <button type="submit">Save Tree Record</button>
      </form>
    );
  },
}));

beforeEach(() => {
  vi.resetAllMocks();
  readDraft.mockReturnValue(null);
});

function renderPage() {
  render(
    <QueryClientProvider client={new QueryClient()}>
      <MemoryRouter initialEntries={["/add-tree"]}>
        <AddTree />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

test("reviewing a nearby tree keeps the unsaved form and photo in place", async () => {
  treesApi.nearby.mockResolvedValue([
    { tree_id: 58, common_name: "Existing tree", distance_m: 3 },
  ]);
  treesApi.get.mockResolvedValue({
    id: 58,
    common_name: "Existing tree",
    photo_url: "/existing.jpg",
    notes: "Near the gate\nAI-estimated DBH and height from photos; not field-validated. Carbon derived from these dimensions is also approximate.",
  });

  renderPage();

  const name = screen.getByLabelText("Common Name");
  const photo = screen.getByLabelText("Tree Photo");
  const file = new File(["tree"], "tree.jpg", { type: "image/jpeg" });
  fireEvent.change(name, { target: { value: "My scanned tree" } });
  fireEvent.change(photo, { target: { files: [file] } });
  fireEvent.click(screen.getByRole("button", { name: "Save Tree Record" }));

  const dialog = await screen.findByRole("dialog");
  fireEvent.click(within(dialog).getByRole("button", { name: "View record" }));
  expect(await within(dialog).findByRole("img", { name: "Existing tree" })).toBeTruthy();
  expect(within(dialog).getByText("Near the gate")).toBeTruthy();
  expect(within(dialog).queryByText(/estimated from photos|not field-validated/i)).toBeNull();
  fireEvent.click(within(dialog).getByRole("button", { name: "Back to nearby trees" }));
  fireEvent.click(within(dialog).getByRole("button", { name: "Cancel" }));

  expect(screen.getByLabelText("Common Name")).toBe(name);
  expect(name.value).toBe("My scanned tree");
  expect(screen.getByLabelText("Tree Photo")).toBe(photo);
  expect(photo.files[0]).toBe(file);
  expect(treesApi.create).not.toHaveBeenCalled();
});


test("an unsent draft with the same species and GPS point still requires review", async () => {
  readDraft.mockReturnValue({
    key: "draft-key",
    status: "draft",
    snapshot: { common_name: "Mango", lat: 7.31, lng: 125.67 },
  });
  treesApi.nearby.mockResolvedValue([
    { tree_id: 58, common_name: "Mango", distance_m: 0, species_match: "exact" },
  ]);

  renderPage();
  fireEvent.change(screen.getByLabelText("Common Name"), { target: { value: "Mango" } });
  fireEvent.click(screen.getByRole("button", { name: "Save Tree Record" }));

  const dialog = await screen.findByRole("dialog");
  expect(within(dialog).getByText(/0 m away.*same species/)).toBeTruthy();
  expect(treesApi.create).not.toHaveBeenCalled();

  treesApi.create.mockResolvedValue({ id: 59 });
  fireEvent.click(within(dialog).getByRole("button", { name: "Register as a new tree" }));
  await waitFor(() => {
    expect(treesApi.create).toHaveBeenCalledWith(expect.objectContaining({ client_uuid: "draft-key" }));
  });
});

test("saving without GPS prompts for confirmation before submitting", async () => {
  renderPage();
  fireEvent.change(screen.getByLabelText("Latitude"), { target: { value: "" } });
  fireEvent.click(screen.getByRole("button", { name: "Save Tree Record" }));

  const dialog = await screen.findByRole("dialog");
  expect(within(dialog).getByText("GPS coordinates needed for duplicate check")).toBeTruthy();
  expect(treesApi.nearby).not.toHaveBeenCalled();
  expect(treesApi.create).not.toHaveBeenCalled();
});
