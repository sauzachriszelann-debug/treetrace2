// G7 tests: durable G2/G4 draft recovery (D5) - sessionStorage stays the
// synchronous view, IndexedDB is the durable mirror, and neither side is
// discarded before the other is confirmed.

import { describe, expect, test } from "vitest";
import { draftGet, draftPut } from "../store";
import {
  TREE_DRAFT_SLOT,
  SUBMISSION_DRAFT_SLOT,
  clearDraft,
  initDrafts,
  persistDraft,
  readDraft,
} from "../drafts";

const treeDraft = {
  key: "11111111-1111-4111-8111-111111111111",
  status: "uncertain",
  created_at: "2026-01-01T00:00:00.000Z",
  snapshot: { common_name: "Narra" },
  original_payload: { common_name: "Narra", lat: 7.5 },
};

describe("persistDraft", () => {
  test("writes the session copy synchronously and mirrors durably", async () => {
    await persistDraft(TREE_DRAFT_SLOT, treeDraft);

    // Sync reader sees it immediately (existing call-site contract).
    expect(readDraft(TREE_DRAFT_SLOT)).toEqual(treeDraft);

    const durable = await draftGet(TREE_DRAFT_SLOT);
    expect(durable).toEqual(treeDraft);
  });

  test("session copy is written even before awaiting the durable mirror", async () => {
    // Call without awaiting: the synchronous part must already be visible,
    // otherwise AddTree's `setDraft(readDraft())` right after writeDraft()
    // would read stale data.
    void persistDraft(SUBMISSION_DRAFT_SLOT, { key: "k1" });
    expect(readDraft(SUBMISSION_DRAFT_SLOT)).toEqual({ key: "k1" });
    await draftGet(SUBMISSION_DRAFT_SLOT); // let the mirror settle
  });
});

describe("initDrafts (tab closed / reload recovery)", () => {
  test("restores a durable-only draft into sessionStorage", async () => {
    // Previous session wrote durably; this session starts with an empty tab.
    await persistDraft(SUBMISSION_DRAFT_SLOT, { key: "sub-key", status: "in_flight" });
    sessionStorage.removeItem(SUBMISSION_DRAFT_SLOT);

    await initDrafts();
    expect(readDraft(SUBMISSION_DRAFT_SLOT)).toEqual({
      key: "sub-key",
      status: "in_flight",
    });
  });

  test("upgrades a session-only draft into durable storage", async () => {
    sessionStorage.setItem(
      TREE_DRAFT_SLOT,
      JSON.stringify({ key: "k", status: "draft" }),
    );

    await initDrafts();
    expect(await draftGet(TREE_DRAFT_SLOT)).toEqual({ key: "k", status: "draft" });
  });

  test("keeps the newer session copy when both exist and differ", async () => {
    await persistDraft(TREE_DRAFT_SLOT, { key: "k", status: "uncertain" });
    // The tab then advanced the draft while a mirror write was lost.
    sessionStorage.setItem(
      TREE_DRAFT_SLOT,
      JSON.stringify({ key: "k", status: "draft", edited: true }),
    );

    await initDrafts();
    expect(await draftGet(TREE_DRAFT_SLOT)).toEqual({
      key: "k",
      status: "draft",
      edited: true,
    });
    expect(readDraft(TREE_DRAFT_SLOT)).toEqual({
      key: "k",
      status: "draft",
      edited: true,
    });
  });

  test("honors a tombstone from a previously failed delete (no resurrection)", async () => {
    sessionStorage.setItem(TREE_DRAFT_SLOT, JSON.stringify({ key: "old" }));
    await draftPut(TREE_DRAFT_SLOT, { cleared: true });

    await initDrafts();
    expect(readDraft(TREE_DRAFT_SLOT)).toBeNull();
    expect(await draftGet(TREE_DRAFT_SLOT)).toBeUndefined();
  });
});

describe("clearDraft (confirm-before-discard)", () => {
  test("removes both copies", async () => {
    await persistDraft(TREE_DRAFT_SLOT, treeDraft);
    await clearDraft(TREE_DRAFT_SLOT);

    expect(readDraft(TREE_DRAFT_SLOT)).toBeNull();
    expect(await draftGet(TREE_DRAFT_SLOT)).toBeUndefined();
  });

  test("a cleared draft does not resurrect after re-init", async () => {
    await persistDraft(TREE_DRAFT_SLOT, treeDraft);
    await clearDraft(TREE_DRAFT_SLOT);
    await initDrafts();
    expect(readDraft(TREE_DRAFT_SLOT)).toBeNull();
    expect(await draftGet(TREE_DRAFT_SLOT)).toBeUndefined();
  });
});
