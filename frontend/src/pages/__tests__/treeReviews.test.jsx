// Phase 10C tests: unified Tree Reviews page (tabs, staff-only guard,
// approve/reject controls, required rejection reason, unknown-species reuse).
// All API calls are MOCKED - no real requests, no submission is altered.

import { describe, expect, test, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
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
  lat: 7.311886,
  lng: 125.67230,
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
  treeSubmissionsApi.convertUnknownSpecies.mockReset();
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

  test("an admin sees one queue with status filters", async () => {
    renderPage();
    expect(screen.getByText("Tree Reviews")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Pending" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Unknown Species" })).toBeNull();
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
    expect(treeSubmissionsApi.list).toHaveBeenCalledWith("all");
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
      expect(screen.getByText(/No submissions in this view/i)).toBeInTheDocument();
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

  test("the Approved filter hides pending records", async () => {
    renderPage();
    await waitFor(() => expect(screen.getByText("Black wattle")).toBeInTheDocument());
    fireEvent.click(screen.getByRole("button", { name: "Approved" }));
    await waitFor(() => {
      expect(screen.queryByText("Black wattle")).toBeNull();
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
    expect(screen.getByRole("dialog", { name: "Approve tree submission" })).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Yes, approve" }));
    await waitFor(() => {
      expect(treeSubmissionsApi.approve).toHaveBeenCalledWith(1, {});
    });
  });

  test("approves using the corrected species names", async () => {
    renderPage();
    await screen.findByText("Black wattle");
    fireEvent.click(approveBtn());
    fireEvent.change(screen.getByLabelText(/Common name for inventory/), { target: { value: " Molave " } });
    fireEvent.change(screen.getByLabelText("Scientific name for inventory"), { target: { value: "Vitex parviflora" } });
    fireEvent.click(screen.getByRole("button", { name: "Yes, approve" }));

    await waitFor(() => expect(treeSubmissionsApi.approve).toHaveBeenCalledWith(1, {
      common_name: "Molave",
      scientific_name: "Vitex parviflora",
    }));
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
    fireEvent.click(screen.getByRole("button", { name: "Approved" }));
    await waitFor(() => expect(screen.getByText("Black wattle")).toBeInTheDocument());
    expect(screen.queryByRole("button", { name: "Approve" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Reject" })).toBeNull();
    expect(screen.getByText(/Reviewed by: Admin/)).toBeInTheDocument();
  });
});

describe("species identification in the unified queue", () => {
  const unknown = {
    id: 17,
    review_status: "pending",
    photo_url: "https://example.test/photo.jpg",
  };

  test("species cards keep submitted notes without user guesses or a question-mark icon", async () => {
    aiApi.listUnknown.mockResolvedValue([{
      ...unknown, possible_name: "Unknown species", submitter_notes: "Tree beside the gate",
    }]);
    renderPage();
    expect(await screen.findByText("Species submission #17")).toBeInTheDocument();
    expect(screen.getByText("Submitted Notes")).toBeInTheDocument();
    expect(screen.getByText("Tree beside the gate")).toBeInTheDocument();
    expect(screen.queryByText("User Guess")).toBeNull();
    expect(document.querySelector(".lucide-circle-help")).toBeNull();
  });

  test("confirmation moves the source record to inventory approval without a duplicate card", async () => {
    aiApi.listUnknown.mockResolvedValue([{
      ...unknown,
      ai_candidates: [{ common_name: "Narra", scientific_name: "Pterocarpus indicus", confidence_percent: 64.45 }],
    }]);
    treeSubmissionsApi.convertUnknownSpecies.mockImplementation(async () => {
      treeSubmissionsApi.list.mockResolvedValue([
        pendingSubmission,
        { ...pendingSubmission, id: 88, common_name: "Molave", scientific_name: "Vitex parviflora", source_unknown_species_id: 17 },
      ]);
      return { id: 88, status: "pending", common_name: "Molave", scientific_name: "Vitex parviflora" };
    });

    renderPage();
    expect(await screen.findByText("Needs Species ID")).toBeInTheDocument();
    expect(screen.getByText("Black wattle")).toBeInTheDocument();
    expect(screen.queryByText("User Guess")).toBeNull();
    expect(screen.getByLabelText("Common name")).toHaveValue("Narra");
    expect(screen.getByLabelText("Scientific name")).toHaveValue("Pterocarpus indicus");
    fireEvent.change(screen.getByLabelText("Common name"), { target: { value: "Molave" } });
    fireEvent.change(screen.getByLabelText("Scientific name"), { target: { value: "Vitex parviflora" } });
    expect(aiApi.reviewUnknown).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: "Confirm Species" }));

    expect(await screen.findByText("Molave")).toBeInTheDocument();
    expect(await screen.findByRole("dialog", { name: "Approve tree submission" })).toBeInTheDocument();
    expect(screen.getByLabelText("Common name for inventory *")).toHaveValue("Molave");
    expect(screen.getByLabelText("Scientific name for inventory")).toHaveValue("Vitex parviflora");
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    expect(screen.queryByRole("dialog")).toBeNull();
    expect(screen.getAllByText("Species submission #17")).toHaveLength(1);
    expect(screen.queryByText("Needs Species ID")).toBeNull();
    expect(aiApi.reviewUnknown).toHaveBeenCalledWith(17, expect.objectContaining({ identified_as: "Molave", identified_scientific_name: "Vitex parviflora" }));
    expect(treeSubmissionsApi.convertUnknownSpecies).toHaveBeenCalledWith(17);
    expect(treeSubmissionsApi.approve).not.toHaveBeenCalled();
  });

  test("field workers use inventory approval without querying the admin identification queue", async () => {
    authState.user = { role: "field_worker", full_name: "FW" };
    renderPage();
    expect(await screen.findByText("Ready for Approval")).toBeInTheDocument();
    expect(aiApi.listUnknown).not.toHaveBeenCalled();
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


describe("inventory boundary review coordinates", () => {
  test("missing GPS prevents approval until the reviewer supplies both coordinates", async () => {
    treeSubmissionsApi.list.mockResolvedValue([{...pendingSubmission, lat:null, lng:null}]);
    renderPage();
    fireEvent.click(await screen.findByRole('button', {name:'Approve', exact:true}));
    fireEvent.click(screen.getByRole('button', {name:'Yes, approve', exact:true}));
    expect(treeSubmissionsApi.approve).not.toHaveBeenCalled();
    fireEvent.change(screen.getByLabelText('Latitude for inventory *'), {target:{value:'7.311886'}});
    fireEvent.change(screen.getByLabelText('Longitude for inventory *'), {target:{value:'125.6723'}});
    fireEvent.click(screen.getByRole('button', {name:'Yes, approve', exact:true}));
    await waitFor(() => expect(treeSubmissionsApi.approve).toHaveBeenCalledWith(1, {lat:7.311886, lng:125.6723}));
  });

  test("a server boundary rejection keeps the review dialog and entered GPS", async () => {
    treeSubmissionsApi.approve.mockRejectedValueOnce({response:{status:422,data:{detail:'This location is outside the Panabo City inventory boundary.'}}});
    renderPage();
    fireEvent.click(await screen.findByRole('button', {name:'Approve',exact:true}));
    fireEvent.change(screen.getByLabelText('Latitude for inventory *'), {target:{value:'7.4475'}});
    fireEvent.change(screen.getByLabelText('Longitude for inventory *'), {target:{value:'125.8078'}});
    fireEvent.click(screen.getByRole('button', {name:'Yes, approve',exact:true}));
    await waitFor(() => expect(treeSubmissionsApi.approve).toHaveBeenCalledWith(1,{lat:7.4475,lng:125.8078}));
    expect(screen.getByRole('dialog', {name:'Approve tree submission'})).toBeInTheDocument();
    expect(screen.getByLabelText('Latitude for inventory *')).toHaveValue(7.4475);
  });
});
