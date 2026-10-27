// G7 tests: durable storage, legacy migration, corruption quarantine, and
// photo Blob durability (D1, requirements 8 & 9).

import { describe, expect, test, vi } from "vitest";
import {
  LEGACY_QUEUE_KEY,
  QueueStore,
  STORE_ITEMS,
  STORE_QUARANTINE,
  uuidFactory,
} from "../store";

function seedLegacy(entries) {
  localStorage.setItem(LEGACY_QUEUE_KEY, JSON.stringify(entries));
}

describe("legacy localStorage import (D1, req 9)", () => {
  test("imports array entries, holds legacy UPDATE_TREE for review, removes key only after read-back", async () => {
    seedLegacy([
      { id: 7, type: "CREATE_TREE", payload: { common_name: "Narra" }, verified: true, timestamp: "2026-01-01T00:00:00.000Z" },
      { id: 8, type: "UPDATE_TREE", payload: { tree_id: 3, notes: "x" }, verified: false },
    ]);

    const store = new QueueStore();
    const result = await store.importLegacyQueue();

    expect(result).toEqual({ imported: 2, skipped: false });
    const items = await store.loadItems();
    expect(items).toHaveLength(2);

    const tree = items.find((i) => i.type === "CREATE_TREE");
    expect(tree.item_id).toMatch(/^[0-9a-f-]{36}$/);
    expect(tree.legacy_id).toBe(7);
    expect(tree.verified).toBe(true);
    expect(tree.hasPhoto).toBe(false);

    // D2: legacy updates are PRESERVED but never eligible for sync.
    const update = items.find((i) => i.type === "UPDATE_TREE");
    expect(update.requires_review).toBe(true);
    expect(update.last_error).toMatch(/re-apply the change manually/i);

    // Removed only after confirmation.
    expect(localStorage.getItem(LEGACY_QUEUE_KEY)).toBeNull();
  });

  test("second import run is a no-op (no duplicates)", async () => {
    seedLegacy([{ id: 1, type: "CREATE_TREE", payload: {} }]);
    const store = new QueueStore();
    await store.importLegacyQueue();
    const again = await store.importLegacyQueue();
    expect(again).toEqual({ imported: 0, skipped: false });
    expect(await store.loadItems()).toHaveLength(1);
  });

  test("unparseable legacy data is preserved, not deleted", async () => {
    localStorage.setItem(LEGACY_QUEUE_KEY, "not-a-json{");
    const store = new QueueStore();
    const result = await store.importLegacyQueue();

    expect(result.preserved).toBe(true);
    expect(localStorage.getItem(LEGACY_QUEUE_KEY)).toBe("not-a-json{");
    expect(store.notice).toMatch(/could not be parsed/i);
    const db = await store.open();
    const quarantined = await db.getAll(STORE_QUARANTINE);
    expect(quarantined).toHaveLength(1);
    expect(quarantined[0].raw).toBe("not-a-json{");
    expect(await store.loadItems()).toHaveLength(0);
  });

  test("unrecognized legacy shape is preserved", async () => {
    localStorage.setItem(LEGACY_QUEUE_KEY, JSON.stringify({ not: "an array" }));
    const store = new QueueStore();
    const result = await store.importLegacyQueue();
    expect(result.preserved).toBe(true);
    expect(localStorage.getItem(LEGACY_QUEUE_KEY)).toBeTruthy();
    expect(store.notice).toMatch(/unrecognized shape/i);
  });
});

describe("damaged records (safeguard 2)", () => {
  test("a structurally damaged item is quarantined and surfaced, never silently dropped", async () => {
    const store = new QueueStore();
    const db = await store.open();
    await db.put(STORE_ITEMS, { item_id: "bad-1", type: 42, payload: "not-an-object" });
    await db.put(STORE_ITEMS, {
      item_id: "good-1",
      type: "CREATE_TREE",
      payload: { common_name: "Acacia" },
      verified: true,
      created_at: "2026-01-01T00:00:00.000Z",
      attempts: 0,
      requires_review: false,
      hasPhoto: false,
    });

    const items = await store.loadItems();
    expect(items.map((i) => i.item_id)).toEqual(["good-1"]);
    expect(store.notice).toMatch(/damaged/i);
    expect(store.notice).toMatch(/preserved/i);

    const quarantined = await db.getAll(STORE_QUARANTINE);
    expect(quarantined).toHaveLength(1);
    expect(quarantined[0].reason).toMatch(/damaged/i);
    // Notice survives reload.
    const reopened = new QueueStore();
    await reopened.loadItems();
    expect(reopened.notice).toMatch(/damaged/i);
  });
});

describe("photo Blob durability (D5, req 2/3)", () => {
  test("photo blobs survive store reopen and are removed only on demand", async () => {
    const blob = new Blob(["fake-image-bytes"], { type: "image/jpeg" });
    const store = new QueueStore();
    await store.putPhoto("item-1", blob);

    // Simulate a browser reload with a fresh store instance.
    const reopened = new QueueStore();
    const stored = await reopened.getPhoto("item-1");
    expect(stored).toBeTruthy();
    expect(stored.size).toBe(blob.size);
    expect(stored.type).toBe("image/jpeg");

    await reopened.deletePhoto("item-1");
    expect(await reopened.getPhoto("item-1")).toBeUndefined();
  });

  test("quota failures are surfaced, not swallowed (req 8)", async () => {
    const store = new QueueStore();
    await store.open();
    const boom = new Error("quota exceeded");
    boom.name = "QuotaExceededError";
    vi.spyOn(store, "open").mockRejectedValue(boom);
    await expect(store.putPhoto("item-1", new Blob(["x"]))).rejects.toThrow();
    expect(store.notice).toMatch(/storage is full/i);
  });
});

describe("serialized writes (req 7)", () => {
  test("concurrent puts do not lose records", async () => {
    const store = new QueueStore();
    const writes = [];
    for (let n = 0; n < 25; n++) {
      writes.push(
        store.putItem({
          item_id: `item-${n}`,
          type: "CREATE_TREE",
          payload: { n },
          verified: false,
          created_at: new Date().toISOString(),
          attempts: 0,
          requires_review: false,
          hasPhoto: false,
        }),
      );
    }
    await Promise.all(writes);
    const db = await store.open();
    expect(await db.count(STORE_ITEMS)).toBe(25);
  });
});

describe("uuidFactory", () => {
  test("generates RFC-4122 v4 identifiers", () => {
    const id = uuidFactory();
    expect(id).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
    );
    expect(uuidFactory()).not.toBe(id);
  });
});
