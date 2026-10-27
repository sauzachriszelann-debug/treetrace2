// G7 tests: the sync engine (a port of G6's OfflineQueueService).
// Covers D3 verified-only sync, bounded retries/backoff, permanent holds,
// ambiguous outcomes, auth aborts, photo-first durability, and citizen
// submission routing (requirements 3, 4, 5, 6).

import { describe, expect, test } from "vitest";
import { QueueStore } from "../store";
import { OfflineQueueService } from "../service";

const httpError = (status, detail) => {
  const error = new Error(`HTTP ${status}`);
  error.response = { status, data: detail !== undefined ? { detail } : undefined };
  return error;
};
const networkError = () => {
  const error = new Error("Network Error");
  error.request = {};
  return error;
};

function makeService({ online = true, clock, sender, uploader } = {}) {
  const store = new QueueStore();
  const calls = [];
  const uploads = [];
  const svc = new OfflineQueueService({
    store,
    isOnline: async () => online,
    sender: sender
      ? sender
      : async (type, payload) => {
          calls.push({ type, payload });
          return { ok: true };
        },
    uploader: uploader
      ? uploader
      : async (blob, purpose) => {
          uploads.push({ blob, purpose });
          return "https://cdn.test/photo.jpg";
        },
    clock: clock ?? (() => Date.now()),
    idFactory: (() => {
      let n = 0;
      return () => `00000000-0000-4000-8000-${String(++n).padStart(12, "0")}`;
    })(),
  });
  return { svc, store, calls, uploads };
}

describe("verified-only synchronization (D3 / requirement 4)", () => {
  test("auto sync sends only previously verified items", async () => {
    const { svc, calls } = makeService();
    const a = await svc.enqueue("CREATE_TREE", { client_uuid: "a" });
    await svc.enqueue("CREATE_TREE", { client_uuid: "b" });
    await svc.setVerified(a.item_id, true);

    const result = await svc.sync({ auto: true });
    expect(result.ran).toBe(true);
    expect(result.synced).toBe(1);
    expect(result.skippedUnverified).toBe(1);
    expect(calls).toHaveLength(1);
    expect(calls[0].payload.client_uuid).toBe("a");
    expect(await svc.count()).toBe(1); // unverified stays queued
  });

  test("manual sync also never uploads unverified items (safeguard)", async () => {
    const { svc, calls } = makeService();
    await svc.enqueue("CREATE_TREE", { client_uuid: "a" });

    const result = await svc.sync({ auto: false });
    expect(result.ran).toBe(true);
    expect(result.synced).toBe(0);
    expect(result.skippedUnverified).toBe(1);
    expect(calls).toHaveLength(0);
  });

  test("offline short-circuits before anything is attempted", async () => {
    const { svc, calls } = makeService({ online: false });
    const item = await svc.enqueue("CREATE_TREE", { client_uuid: "a" });
    await svc.setVerified(item.item_id, true);

    const result = await svc.sync({ auto: true });
    expect(result.offline).toBe(true);
    expect(calls).toHaveLength(0);
  });

  test("held records are skipped by BOTH auto and manual sync", async () => {
    const { svc, calls } = makeService();
    const item = await svc.enqueue("CREATE_TREE", { client_uuid: "a" }, {
      requiresReview: true,
      reviewReason: "held",
    });
    await svc.setVerified(item.item_id, true);

    for (const auto of [true, false]) {
      const result = await svc.sync({ auto });
      expect(result.heldForReview).toBe(1);
      expect(calls).toHaveLength(0);
    }

    // Only the explicit per-item retry clears the hold.
    await svc.resolveForManualRetry(item.item_id);
    await svc.sync({ auto: false });
    expect(calls).toHaveLength(1);
  });
});

describe("retries, backoff and exhaustion (D3)", () => {
  test("retryable failure backs off; manual sync ignores the window", async () => {
    let now = 1_000_000;
    const { svc, calls } = makeService({
      clock: () => now,
      sender: async () => {
        calls.push(1);
        throw httpError(503);
      },
    });
    const item = await svc.enqueue("CREATE_TREE", { client_uuid: "a" });
    await svc.setVerified(item.item_id, true);

    const first = await svc.sync({ auto: true });
    expect(first.keptForRetry).toBe(1);
    expect(calls).toHaveLength(1);
    const stored = (await svc.all())[0];
    expect(stored.attempts).toBe(1);
    expect(stored.next_retry_at_ms).toBe(now + 30000);

    // Auto within the window: skipped.
    const second = await svc.sync({ auto: true });
    expect(second.skippedBackoff).toBe(1);
    expect(calls).toHaveLength(1);

    // Manual (user intent) proceeds regardless.
    const manual = await svc.sync({ auto: false });
    expect(manual.ran).toBe(true);
    expect(calls).toHaveLength(2);

    // After the window (attempt 2 => 60s), auto retries again.
    now += 70001;
    await svc.sync({ auto: true });
    expect(calls).toHaveLength(3);
  });

  test("auto attempts cap at 5 then hold as retries_exhausted", async () => {
    let now = 1_000_000;
    const { svc, calls } = makeService({
      clock: () => now,
      sender: async () => {
        calls.push(1);
        throw httpError(503);
      },
    });
    const item = await svc.enqueue("CREATE_TREE", { client_uuid: "a" });
    await svc.setVerified(item.item_id, true);

    for (let i = 0; i < 6; i++) {
      await svc.sync({ auto: true });
      now += 60 * 60 * 1000; // jump past any backoff
    }
    expect(calls).toHaveLength(5); // never a 6th automatic attempt
    const stored = (await svc.all())[0];
    expect(stored.requires_review).toBe(true);
    expect(stored.last_error_kind).toBe("retries_exhausted");
  });
});

describe("conflicts and uncertain outcomes are never auto-retried (req 6)", () => {
  test("409 conflict holds the record and a later auto sync does not resend", async () => {
    const { svc, calls } = makeService({
      sender: async (type, payload) => {
        calls.push({ type, payload });
        throw httpError(409, "already exists");
      },
    });
    const item = await svc.enqueue("CREATE_TREE", { client_uuid: "a" });
    await svc.setVerified(item.item_id, true);

    const first = await svc.sync({ auto: true });
    expect(first.heldForReview).toBe(1);
    const stored = (await svc.all())[0];
    expect(stored.requires_review).toBe(true);
    expect(stored.last_error_kind).toBe("conflict");
    expect(stored.last_error).toBe("already exists");

    const second = await svc.sync({ auto: true });
    expect(second.heldForReview).toBe(1);
    expect(calls).toHaveLength(1); // exactly one attempt, ever
  });

  test("ambiguous health-log failure holds the record (no idempotency key)", async () => {
    const { svc, calls } = makeService({
      sender: async (type, payload) => {
        calls.push({ type, payload });
        throw networkError();
      },
    });
    const item = await svc.enqueue("CREATE_HEALTH_LOG", { tree_id: 1 });
    await svc.setVerified(item.item_id, true);

    const first = await svc.sync({ auto: true });
    expect(first.heldForReview).toBe(1);
    const stored = (await svc.all())[0];
    expect(stored.last_error_kind).toBe("ambiguous");
    expect(stored.requires_review).toBe(true);

    await svc.sync({ auto: true });
    await svc.sync({ auto: false });
    expect(calls).toHaveLength(1); // blind replay NEVER happens
  });

  test("idempotent type retries safely on the same failure", async () => {
    const { svc, calls } = makeService({
      sender: async (type, payload) => {
        calls.push({ type, payload });
        throw networkError();
      },
    });
    const item = await svc.enqueue("CREATE_TREE", { client_uuid: "a" });
    await svc.setVerified(item.item_id, true);

    const result = await svc.sync({ auto: true });
    expect(result.keptForRetry).toBe(1); // safe: client_uuid dedupes
    expect(result.heldForReview).toBe(0);
    expect(calls).toHaveLength(1);
  });

  test("quota 402 is retryable, not a hold, and reports the server message", async () => {
    const { svc } = makeService({
      sender: async () => {
        throw httpError(402, "You've used all 10 tree submissions for today.");
      },
    });
    const item = await svc.enqueue("CREATE_TREE_SUBMISSION", { client_uuid: "s" });
    await svc.setVerified(item.item_id, true);

    const result = await svc.sync({ auto: false });
    expect(result.keptForRetry).toBe(1);
    expect(result.heldForReview).toBe(0);
    const stored = (await svc.all())[0];
    expect(stored.requires_review).toBe(false);
    expect(stored.last_error).toContain("all 10 tree submissions");
  });
});

describe("authentication during sync (D4)", () => {
  test("401 aborts the run, keeps every record, and reports authError", async () => {
    let should401 = true;
    const { svc, calls } = makeService({
      sender: async (type, payload) => {
        calls.push({ type, payload });
        if (should401) throw httpError(401, "Token expired");
        return { ok: true };
      },
    });
    const a = await svc.enqueue("CREATE_TREE", { client_uuid: "a" });
    const b = await svc.enqueue("CREATE_TREE", { client_uuid: "b" });
    await svc.setVerified(a.item_id, true);
    await svc.setVerified(b.item_id, true);

    const result = await svc.sync({ auto: false });
    expect(result.authError).toBe("Token expired");
    expect(calls).toHaveLength(1); // aborted after the first 401
    expect(await svc.count()).toBe(2); // queue survives (safeguard 4)

    // After re-auth the same records sync normally.
    should401 = false;
    const retry = await svc.sync({ auto: false });
    expect(retry.synced).toBe(2);
    expect(await svc.count()).toBe(0);
  });
});

describe("photo-first durability (D5 / requirement 3)", () => {
  test("uploads photo before the record; both removed only after both succeed", async () => {
    const { svc, store, calls, uploads } = makeService();
    const item = await svc.enqueue("CREATE_TREE", { client_uuid: "a" }, {
      photoBlob: new Blob(["img"], { type: "image/jpeg" }),
    });
    await svc.setVerified(item.item_id, true);

    const result = await svc.sync({ auto: false });
    expect(result.synced).toBe(1);
    expect(uploads).toHaveLength(1);
    expect(calls[0].payload.photo_url).toBe("https://cdn.test/photo.jpg");
    expect(await svc.count()).toBe(0);
    expect(await store.getPhoto(item.item_id)).toBeUndefined(); // only after success
  });

  test("record is NOT created without its photo, and the photo is kept", async () => {
    const { svc, store, calls } = makeService({
      uploader: async () => {
        throw httpError(503, "storage down");
      },
    });
    const item = await svc.enqueue("CREATE_TREE", { client_uuid: "a" }, {
      photoBlob: new Blob(["img"]),
    });
    await svc.setVerified(item.item_id, true);

    const result = await svc.sync({ auto: false });
    expect(result.synced).toBe(0);
    expect(calls).toHaveLength(0);
    expect(await svc.count()).toBe(1);
    expect(await store.getPhoto(item.item_id)).toBeTruthy(); // D5: kept

    const stored = (await svc.all())[0];
    expect(stored.attempts).toBe(1);
    expect(stored.last_error).toMatch(/photo upload failed/i);
  });

  test("a completed photo upload is never repeated on retry", async () => {
    let failSend = true;
    const { svc, calls, uploads } = makeService({
      sender: async (type, payload) => {
        if (failSend) throw httpError(503);
        calls.push({ type, payload });
        return { ok: true };
      },
    });
    const item = await svc.enqueue("CREATE_TREE", { client_uuid: "a" }, {
      photoBlob: new Blob(["img"]),
    });
    await svc.setVerified(item.item_id, true);

    await svc.sync({ auto: false }); // upload ok, send fails
    expect(uploads).toHaveLength(1);
    failSend = false;
    await svc.sync({ auto: false }); // retry: no second upload

    expect(uploads).toHaveLength(1);
    expect(calls).toHaveLength(1);
    expect(calls[0].payload.photo_url).toBe("https://cdn.test/photo.jpg");
    expect(await svc.count()).toBe(0);
  });

  test("missing photo blob holds the record; explicit consent releases it", async () => {
    const { svc, store, calls } = makeService();
    const item = await svc.enqueue("CREATE_TREE", { client_uuid: "a" }, {
      photoBlob: new Blob(["img"]),
    });
    await svc.setVerified(item.item_id, true);
    await store.deletePhoto(item.item_id); // storage lost the blob

    const result = await svc.sync({ auto: false });
    expect(result.heldForReview).toBe(1);
    expect(calls).toHaveLength(0);
    let stored = (await svc.all())[0];
    expect(stored.last_error_kind).toBe("missing_photo");
    expect(stored.requires_review).toBe(true);

    await svc.continueWithoutPhoto(item.item_id);
    stored = (await svc.all())[0];
    expect(stored.requires_review).toBe(false);
    expect(stored.hasPhoto).toBe(false);

    const retry = await svc.sync({ auto: false });
    expect(retry.synced).toBe(1);
    expect(calls).toHaveLength(1);
  });
});

describe("citizen routing and source defaults (D2 / requirement 5)", () => {
  test("CREATE_TREE_SUBMISSION sends client_uuid and defaults source=mobile", async () => {
    const { svc, calls } = makeService();
    const item = await svc.enqueue("CREATE_TREE_SUBMISSION", {
      client_uuid: "sub-1",
      common_name: "Narra",
    });
    await svc.setVerified(item.item_id, true);

    await svc.sync({ auto: false });
    expect(calls[0].type).toBe("CREATE_TREE_SUBMISSION");
    expect(calls[0].payload.client_uuid).toBe("sub-1");
    expect(calls[0].payload.source).toBe("mobile");
  });

  test("an explicit source (ai_identify) is preserved", async () => {
    const { svc, calls } = makeService();
    const item = await svc.enqueue("CREATE_TREE_SUBMISSION", {
      client_uuid: "sub-2",
      source: "ai_identify",
    });
    await svc.setVerified(item.item_id, true);

    await svc.sync({ auto: false });
    expect(calls[0].payload.source).toBe("ai_identify");
  });

  test("citizen submission photos upload with the citizen-allowed purpose", async () => {
    const { svc, uploads } = makeService();
    const item = await svc.enqueue(
      "CREATE_TREE_SUBMISSION",
      { client_uuid: "sub-3" },
      { photoBlob: new Blob(["img"]) },
    );
    await svc.setVerified(item.item_id, true);

    await svc.sync({ auto: false });
    expect(uploads[0].purpose).toBe("unknown_species");
  });
});

describe("store integration", () => {
  test("queue state survives a service restart (reload recovery)", async () => {
    const first = makeService();
    const a = await first.svc.enqueue("CREATE_TREE", { client_uuid: "a" });
    await first.svc.enqueue("CREATE_HEALTH_LOG", { tree_id: 9 });
    await first.svc.setVerified(a.item_id, true);

    // "Reload": brand-new service over the same IndexedDB.
    const second = makeService();
    const items = await second.svc.all();
    expect(items).toHaveLength(2);
    expect(items.find((i) => i.type === "CREATE_TREE").verified).toBe(true);

    const result = await second.svc.sync({ auto: true });
    expect(result.synced).toBe(1);
    expect(result.skippedUnverified).toBe(1);
  });
});
