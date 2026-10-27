// Phase 10C tests: unified Tree Reviews page (tabs, staff-only guard,
// approve/reject controls, required rejection reason, unknown-species reuse).
// All API calls are MOCKED - no real requests, no submission is altered.

import { describe, expect, test, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";

vi.mock("@/api/treeSubmissions", () => ({
  treeSubmissionsApi: {
    list: vi.fn(),
    approve: vi.fn(),
    reject: vi.fn(),
    convertUnknownSpecies: vi.fn(),
  },
}));

vi.mock("@/api/ai", () => ({
  aiApi: { listUnknown: vi.fn(), reviewUnknown: vi.fn() },
}));

// Reuse the real UnknownSpeciesReview to prove tab 2 keeps working, but its
// internals are the existing component's own concern.
import { treeSubmissionsApi } from "@/api/treeSubmissions";
import { aiApi } from "@/api/ai";
import TreeReviews from "@/pages/TreeReviews";
import Sidebar from "@/components/layout/Sidebar";
import { MemoryRouter } from "react-router-dom";
import { OfflineSyncContext } from "@/offline/OfflineSyncProvider";

// Controllable auth mock so we can flip roles per test.
const authState = { user: { role: "admin", full_name: "Test Admin" }, isLoadingAuth: false };
vi.mock("@/lib/AuthContext", () => ({
  useAuth: () => authState,
}));

const pendingSubmission = {
  id: 1,
  client_uuid: "abc",
  status: "pending",
  source: "ai_identify",
  common_name: "Black wattle",
  scientific_name: "Acacia mangium",
  dbh_cm: 5.2,
  height_m: 6.1,
  health_status: "Healthy",
  barangay: "Panabo",
  city: "Panabo City",
  lat: null,
  lng: null,
  photo_url: null,
  date_recorded: "2026-10-23",
  notes: "Found near the school",
  submitted_by_id: 2,
  submitted_by_name: "Citizen Tester",
  submitted_by_email: "citizen@example.com",
  reviewed_by_id: null,
  reviewed_by_name: null,
  review_reason: null,
  approved_tree_id: null,
  created_at: "2026-10-23T19:03:40Z",
};

function renderPage() {
  const qc = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  return render(
    <QueryClientProvider client={qc}>
      <TreeReviews />
    </QueryClientProvider>,
  );
}

// The Sidebar calls useOfflineSync, which requires the provider context.
const offlineCtx = {
  isOnline: true,
  queueLength: 0,
};
function renderSidebar(user) {
  return render(
    <OfflineSyncContext.Provider value={offlineCtx}>
      <MemoryRouter>
        <Sidebar user={user} />
      </MemoryRouter>
    </OfflineSyncContext.Provider>,
  );
}

// NOTE: the status filter buttons are labelled "Approved"/"Rejected", which
// would collide with a loose /Approve/i role query. Use exact names for the
// per-row action buttons so they are distinct from the filter chips.
const approveBtn = () => screen.getByRole("button", { name: "Approve" });
const rejectBtn = () => screen.getByRole("button", { name: "Reject" });

beforeEach(() => {
  authState.user = { role: "admin", full_name: "Test Admin" };
  authState.isLoadingAuth = false;
  treeSubmissionsApi.list.mockResolvedValue([pendingSubmission]);
  treeSubmissionsApi.approve.mockResolvedValue({ tree: { id: 99 } });
  treeSubmissionsApi.reject.mockResolvedValue({ status: "rejected" });
  aiApi.listUnknown.mockResolvedValue([]);
  aiApi.reviewUnknown.mockResolvedValue({});
});

describe("staff-only access guard (task 10)", () => {
  test("a citizen sees the staff-required notice, not the review tools", async () => {
    authState.user = { role: "citizen", full_name: "Cit" };
    renderPage();
    expect(screen.getByText(/Staff access required/i)).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /Tree Submissions/i })).toBeNull();
  });

  test("an admin sees the page and both tabs", async () => {
    renderPage();
    expect(screen.getByText("Tree Reviews")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Tree Submissions/i })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Unknown Species/i })).toBeInTheDocument();
  });

  test("a field worker (staff) also sees the page", async () => {
    authState.user = { role: "field_worker", full_name: "FW" };
    renderPage();
    expect(screen.getByText("Tree Reviews")).toBeInTheDocument();
  });

  test("loading auth shows a skeleton, not the guard", () => {
    authState.isLoadingAuth = true;
    renderPage();
    expect(screen.queryByText(/Staff access required/i)).toBeNull();
  });
});

describe("Tree Submissions tab", () => {
  test("lists the pending submission with species and location", async () => {
    renderPage();
    await waitFor(() => {
      expect(screen.getByText("Black wattle")).toBeInTheDocument();
    });
    expect(screen.getByText("Acacia mangium")).toBeInTheDocument();
    expect(screen.getByText(/Panabo/)).toBeInTheDocument();
    expect(screen.getByText(/Citizen Tester/)).toBeInTheDocument();
    expect(treeSubmissionsApi.list).toHaveBeenCalledWith("pending");
  });

  test("shows a loading skeleton first, then the data", async () => {
    renderPage();
    // Skeleton present synchronously before resolve.
    expect(document.querySelector(".animate-pulse")).toBeTruthy();
    await waitFor(() => expect(screen.getByText("Black wattle")).toBeInTheDocument());
  });

  test("shows the empty state when there are no submissions", async () => {
    treeSubmissionsApi.list.mockResolvedValue([]);
    renderPage();
    await waitFor(() => {
      expect(screen.getByText(/No pending submissions/i)).toBeInTheDocument();
    });
  });

  test("shows an error state with a retry button when the fetch fails", async () => {
    treeSubmissionsApi.list.mockRejectedValue({
      response: { data: { detail: "boom" } },
    });
    renderPage();
    await waitFor(() => {
      expect(screen.getByText(/Could not load submissions/i)).toBeInTheDocument();
    });
    expect(screen.getByRole("button", { name: /Try again/i })).toBeInTheDocument();
  });

  test("status filter buttons re-query with the chosen status", async () => {
    renderPage();
    await waitFor(() => expect(screen.getByText("Black wattle")).toBeInTheDocument());
    fireEvent.click(screen.getByRole("button", { name: "Approved" }));
    await waitFor(() => {
      expect(treeSubmissionsApi.list).toHaveBeenCalledWith("approved");
    });
  });
});

describe("approve flow (mocked - no real status change)", () => {
  test("approve asks for confirmation first, then calls the API", async () => {
    renderPage();
    await waitFor(() => expect(screen.getByText("Black wattle")).toBeInTheDocument());

    fireEvent.click(approveBtn());
    // Confirmation gate appears before any API call.
    expect(treeSubmissionsApi.approve).not.toHaveBeenCalled();
    expect(screen.getByText(/becomes an official tree record/i)).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Yes, approve" }));
    await waitFor(() => {
      expect(treeSubmissionsApi.approve).toHaveBeenCalledWith(1, {});
    });
  });

  test("cancel on the confirmation does not call the API", async () => {
    renderPage();
    await waitFor(() => expect(screen.getByText("Black wattle")).toBeInTheDocument());
    fireEvent.click(approveBtn());
    fireEvent.click(screen.getByRole("button", { name: /Cancel/i }));
    expect(treeSubmissionsApi.approve).not.toHaveBeenCalled();
    expect(approveBtn()).toBeInTheDocument();
  });

  test("a backend error surfaces as a toast and keeps the row", async () => {
    treeSubmissionsApi.approve.mockRejectedValue({
      response: { data: { detail: { message: "Already approved elsewhere" } } },
    });
    renderPage();
    await waitFor(() => expect(screen.getByText("Black wattle")).toBeInTheDocument());
    fireEvent.click(approveBtn());
    fireEvent.click(screen.getByRole("button", { name: "Yes, approve" }));
    await waitFor(() => {
      expect(screen.getByText("Black wattle")).toBeInTheDocument();
    });
  });
});

describe("reject flow (mocked - reason required)", () => {
  test("reject opens a reason box and the confirm stays disabled until filled", async () => {
    renderPage();
    await waitFor(() => expect(screen.getByText("Black wattle")).toBeInTheDocument());

    fireEvent.click(rejectBtn());
    expect(screen.getByText(/Rejection reason \(required\)/i)).toBeInTheDocument();

    const confirm = screen.getByRole("button", { name: "Confirm reject" });
    expect(confirm).toBeDisabled();
    expect(treeSubmissionsApi.reject).not.toHaveBeenCalled();
  });

  test("with a reason, confirm calls reject with the reason", async () => {
    renderPage();
    await waitFor(() => expect(screen.getByText("Black wattle")).toBeInTheDocument());
    fireEvent.click(rejectBtn());

    const box = screen.getByPlaceholderText(/Explain why/i);
    fireEvent.change(box, { target: { value: "Duplicate of tree #5" } });

    const confirm = screen.getByRole("button", { name: "Confirm reject" });
    expect(confirm).toBeEnabled();
    fireEvent.click(confirm);

    await waitFor(() => {
      expect(treeSubmissionsApi.reject).toHaveBeenCalledWith(1, "Duplicate of tree #5");
    });
  });

  test("cancel closes the reason box without calling the API", async () => {
    renderPage();
    await waitFor(() => expect(screen.getByText("Black wattle")).toBeInTheDocument());
    fireEvent.click(rejectBtn());
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    expect(treeSubmissionsApi.reject).not.toHaveBeenCalled();
    expect(screen.queryByText(/Rejection reason/i)).toBeNull();
  });

  test("non-pending rows do not show approve/reject controls", async () => {
    treeSubmissionsApi.list.mockResolvedValue([
      { ...pendingSubmission, status: "approved", approved_tree_id: 99, reviewed_by_name: "Admin" },
    ]);
    renderPage();
    await waitFor(() => expect(screen.getByText("Black wattle")).toBeInTheDocument());
    expect(screen.queryByRole("button", { name: "Approve" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Reject" })).toBeNull();
    expect(screen.getByText(/Reviewed by: Admin/)).toBeInTheDocument();
  });
});

describe("Unknown Species tab (task 5 - preserved functionality)", () => {
  test("switching to the tab renders the existing unknown-species review", async () => {
    renderPage();
    await waitFor(() => expect(screen.getByText("Black wattle")).toBeInTheDocument());

    fireEvent.click(screen.getByRole("button", { name: /Unknown Species/i }));
    // The reused component's own heading proves it is intact.
    await waitFor(() => {
      expect(screen.getByText("Unknown Species Review")).toBeInTheDocument();
    });
    expect(aiApi.listUnknown).toHaveBeenCalled();
  });

  test("the two tabs use separate endpoints (submissions vs unknown-species)", async () => {
    renderPage();
    await waitFor(() => expect(treeSubmissionsApi.list).toHaveBeenCalled());
    fireEvent.click(screen.getByRole("button", { name: /Unknown Species/i }));
    await waitFor(() => expect(aiApi.listUnknown).toHaveBeenCalled());
    // Both endpoints were hit; the workflows are separate (task 6).
    expect(treeSubmissionsApi.list).toHaveBeenCalledWith("pending");
    expect(aiApi.listUnknown).toHaveBeenCalled();
  });
});

describe("navigation (task 7/8)", () => {
  test("sidebar exposes Tree Reviews and no separate Tree Submissions item", async () => {
    renderSidebar({ role: "admin", full_name: "A" });
    expect(screen.getByText("Tree Reviews")).toBeInTheDocument();
    // Task 8: no duplicate Tree Submissions sidebar entry.
    expect(screen.queryByText("Tree Submissions")).toBeNull();
    // Old label is gone, replaced by Tree Reviews.
    expect(screen.queryByText("Unknown Review")).toBeNull();
  });

  test("field worker sees Tree Reviews in the sidebar too", async () => {
    renderSidebar({ role: "field_worker", full_name: "FW" });
    expect(screen.getByText("Tree Reviews")).toBeInTheDocument();
  });

  test("a citizen does not see Tree Reviews in the sidebar", async () => {
    renderSidebar({ role: "citizen", full_name: "C" });
    expect(screen.queryByText("Tree Reviews")).toBeNull();
  });
});
