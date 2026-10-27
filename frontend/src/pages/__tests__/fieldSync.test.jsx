// G7 tests: Field Sync Review UI states (D8) - per-item statuses, review
// holds with reasons, session/quota banners, disabled sync rules, and the
// honest storage-eviction disclaimer (requirement 12).

import { describe, expect, test, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { OfflineSyncContext } from "@/offline/OfflineSyncProvider";
import FieldSync from "@/pages/FieldSync";

const baseContext = {
  ready: true,
  isOnline: true,
  queue: [],
  queueLength: 0,
  syncing: false,
  result: null,
  notice: null,
  autoSyncAvailable: true,
  enqueue: vi.fn(),
  setVerified: vi.fn(),
  verifyAll: vi.fn(),
  remove: vi.fn(),
  retryOnce: vi.fn(),
  continueWithoutPhoto: vi.fn(),
  syncNow: vi.fn(),
  refresh: vi.fn(),
  dismissNotice: vi.fn(),
  getPhoto: vi.fn(async () => null),
  setResult: vi.fn(),
};

function renderPage(overrides = {}) {
  const value = { ...baseContext, ...overrides };
  return render(
    <OfflineSyncContext.Provider value={value}>
      <FieldSync />
    </OfflineSyncContext.Provider>,
  );
}

const heldItem = {
  item_id: "i1",
  type: "CREATE_HEALTH_LOG",
  payload: { tree_id: 3 },
  verified: true,
  requires_review: true,
  last_error_kind: "ambiguous",
  last_error:
    "The request may have already reached the server. A blind retry could create a duplicate health log.",
  attempts: 1,
  hasPhoto: false,
  created_at: "2026-01-01T10:00:00.000Z",
};

describe("empty and loading states", () => {
  test("empty queue shows the review copy", () => {
    renderPage();
    expect(
      screen.getByText("No offline records waiting for review."),
    ).toBeInTheDocument();
    expect(screen.getByText(/0 pending/)).toBeInTheDocument();
  });

  test("storage eviction limits are always disclosed (req 12)", () => {
    renderPage();
    expect(screen.getByText(/may evict site data/i)).toBeInTheDocument();
    expect(screen.queryByText(/guaranteed delivery/i)).not.toBeInTheDocument();
  });
});

describe("review holds and per-item status (D8)", () => {
  test("held record shows its label, reason, and status - and sync stays disabled", () => {
    renderPage({ queue: [heldItem] });

    expect(screen.getByText(/Possible duplicate - review/)).toBeInTheDocument();
    expect(screen.getByText(/duplicate health log/)).toBeInTheDocument();
    expect(
      screen.getByText("Verified - held for review"),
    ).toBeInTheDocument();
    expect(screen.getByText("Retry once")).toBeInTheDocument();

    // Nothing verified+syncable => Sync Verified disabled (safeguard 9).
    expect(
      screen.getByRole("button", { name: /Sync Verified/ }),
    ).toBeDisabled();
    expect(screen.getByText(/1 need review/)).toBeInTheDocument();
  });

  test("unverified record reads Needs your verification and cannot sync", () => {
    renderPage({
      queue: [{ ...heldItem, verified: false, requires_review: false, last_error: null, last_error_kind: null }],
    });
    expect(screen.getByText("Needs your verification")).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /Sync Verified/ }),
    ).toBeDisabled();
  });

  test("a verified, clean record enables Sync Verified which triggers a manual run", () => {
    const syncNow = vi.fn();
    renderPage({
      queue: [
        {
          ...heldItem,
          requires_review: false,
          last_error: null,
          last_error_kind: null,
        },
      ],
      syncNow,
    });
    expect(
      screen.getByRole("button", { name: /Sync Verified/ }),
    ).toBeEnabled();
    fireEvent.click(screen.getByRole("button", { name: /Sync Verified/ }));
    expect(syncNow).toHaveBeenCalledWith({ auto: false });
  });

  test("missing photo shows the warning and the explicit escape hatch", () => {
    const continueWithoutPhoto = vi.fn();
    renderPage({
      queue: [
        {
          ...heldItem,
          last_error_kind: "missing_photo",
          last_error:
            "The photo for this record is missing from browser storage. Continue without the photo or remove the record.",
          hasPhoto: true,
        },
      ],
      continueWithoutPhoto,
    });

    expect(screen.getByText(/Photo missing on device/)).toBeInTheDocument();
    // The reason text and the dedicated warning both explain the missing photo.
    expect(
      screen.getAllByText(/photo for this record is missing/i).length,
    ).toBeGreaterThan(0);
    const escape = screen.getByRole("button", { name: /Sync w\/o photo/ });
    fireEvent.click(escape);
    expect(continueWithoutPhoto).toHaveBeenCalledWith("i1");
  });

  test("citizen submissions are labelled as pending approval", () => {
    renderPage({
      queue: [
        {
          ...heldItem,
          type: "CREATE_TREE_SUBMISSION",
          payload: { common_name: "Narra", client_uuid: "sub-1" },
          requires_review: false,
          last_error: null,
          last_error_kind: null,
        },
      ],
    });
    expect(
      screen.getByText(/Tree submission \(pending approval\)/),
    ).toBeInTheDocument();
  });
});

describe("run banners", () => {
  test("session expiry keeps the queue visible with the safe-keeping message", () => {
    renderPage({
      queue: [heldItem],
      result: {
        ran: true,
        alreadyRunning: false,
        offline: false,
        synced: 0,
        heldForReview: 0,
        keptForRetry: 0,
        skippedUnverified: 0,
        skippedBackoff: 0,
        authError: "Token expired",
      },
    });
    expect(screen.getByText(/Session expired/)).toBeInTheDocument();
    expect(screen.getByText(/kept on this device/)).toBeInTheDocument();
    // The records themselves are still rendered.
    expect(screen.getByText(/Possible duplicate - review/)).toBeInTheDocument();
  });

  test("a mixed run reports synced, held, retried and skipped counts", () => {
    renderPage({
      result: {
        ran: true,
        alreadyRunning: false,
        offline: false,
        synced: 2,
        heldForReview: 1,
        keptForRetry: 1,
        skippedUnverified: 3,
        skippedBackoff: 0,
        authError: null,
      },
    });
    expect(screen.getByText(/Synced 2\./)).toBeInTheDocument();
    expect(screen.getByText(/1 held for your review/)).toBeInTheDocument();
    expect(screen.getByText(/1 waiting to retry/)).toBeInTheDocument();
    expect(screen.getByText(/3 skipped: not verified yet/)).toBeInTheDocument();
  });

  test("offline shows the reconnect behavior, honest about manual sync when locks are missing", () => {
    renderPage({ isOnline: false, autoSyncAvailable: false });
    expect(
      screen.getByText(/Offline\. Verified records wait here for manual sync/),
    ).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Sync Verified/ })).toBeDisabled();
  });

  test("missing Web Locks disables auto sync with an explanation (D7)", () => {
    renderPage({ autoSyncAvailable: false });
    expect(screen.getByText(/Automatic sync is disabled/)).toBeInTheDocument();
    expect(screen.getByText(/Web Locks/)).toBeInTheDocument();
  });

  test("storage corruption/quota notices surface with a dismiss action", () => {
    const dismissNotice = vi.fn();
    renderPage({
      notice: "The offline queue file was damaged. Its contents were preserved.",
      dismissNotice,
    });
    expect(screen.getByText(/was damaged/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Dismiss" }));
    expect(dismissNotice).toHaveBeenCalled();
  });
});
