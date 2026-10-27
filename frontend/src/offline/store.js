// G7 (D1): IndexedDB-backed storage for the offline queue.
//
// Design mirrors G6's file-backed Flutter store:
//  * structured records live in the `items` store (keyPath item_id);
//  * photo Blobs live in the `photos` store keyed by item_id;
//  * all mutations are serialized through one write chain so concurrent
//    writers can never overwrite newer state (safeguard 7);
//  * unparseable/unrecognized records are MOVED to a `quarantine` store and
//    surfaced through a notice - never silently deleted (safeguard 2);
//  * the legacy localStorage queue is imported once, non-destructively: the
//    original key is removed only after a read-back confirms the import.

import { openDB } from "idb";

export const DB_NAME = "treetrace_offline";
export const DB_VERSION = 1;
export const LEGACY_QUEUE_KEY = "treetrace_offline_queue";

export const STORE_ITEMS = "items";
export const STORE_PHOTOS = "photos";
export const STORE_DRAFTS = "drafts";
export const STORE_META = "meta";
export const STORE_QUARANTINE = "quarantine";

export function uuidFactory() {
  if (typeof crypto !== "undefined" && crypto.randomUUID) {
    return crypto.randomUUID();
  }
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function isValidItem(item) {
  return (
    item !== null &&
    typeof item === "object" &&
    typeof item.item_id === "string" &&
    item.item_id.length > 0 &&
    typeof item.type === "string" &&
    item.payload !== null &&
    typeof item.payload === "object" &&
    !Array.isArray(item.payload)
  );
}

function upgradeDB(db) {
  if (!db.objectStoreNames.contains(STORE_ITEMS)) {
    db.createObjectStore(STORE_ITEMS, { keyPath: "item_id" });
  }
  if (!db.objectStoreNames.contains(STORE_PHOTOS)) {
    db.createObjectStore(STORE_PHOTOS);
  }
  if (!db.objectStoreNames.contains(STORE_DRAFTS)) {
    db.createObjectStore(STORE_DRAFTS);
  }
  if (!db.objectStoreNames.contains(STORE_META)) {
    db.createObjectStore(STORE_META);
  }
  if (!db.objectStoreNames.contains(STORE_QUARANTINE)) {
    db.createObjectStore(STORE_QUARANTINE, {
      keyPath: "id",
      autoIncrement: true,
    });
  }
}

export class QueueStore {
  constructor() {
    this._db = null;
    this._writeChain = Promise.resolve();
    this.notice = null; // corruption / quota notices surfaced to the UI
  }

  async open() {
    if (this._db) return this._db;
    this._db = await openDB(DB_NAME, DB_VERSION, { upgrade: upgradeDB });
    return this._db;
  }

  _setNotice(message) {
    this.notice = this.notice ? `${this.notice} ${message}` : message;
  }

  /// Serializes every mutation; each call snapshots state at enqueue time so
  /// interleaved writes cannot lose records (requirement 7).
  _enqueueWrite(fn) {
    const run = this._writeChain.then(fn, fn);
    // Keep the chain alive even when fn rejects; the caller still sees it.
    this._writeChain = run.catch(() => {});
    return run;
  }

  async _metaGet(key) {
    const db = await this.open();
    return db.get(STORE_META, key);
  }

  async _metaSet(key, value) {
    const db = await this.open();
    return db.put(STORE_META, value, key);
  }

  async quarantineRecord(raw, reason) {
    const db = await this.open();
    await db.put(STORE_QUARANTINE, {
      raw,
      reason,
      quarantined_at: new Date().toISOString(),
    });
    this._setNotice(
      `${reason} The original data was preserved under "quarantine" for manual recovery and was NOT replayed automatically.`,
    );
    await this._metaSet("notice", this.notice);
  }

  /// Validates every stored record; damaged entries are quarantined, never
  /// dropped. Returns the list of healthy items.
  async loadItems() {
    const db = await this.open();
    const all = await db.getAll(STORE_ITEMS);
    const healthy = [];
    const damaged = [];
    for (const item of all) {
      if (isValidItem(item)) {
        healthy.push(item);
      } else {
        damaged.push(item);
      }
    }
    for (const bad of damaged) {
      try {
        await this.quarantineRecord(bad, "An offline queue record was damaged.");
        if (bad && typeof bad === "object" && typeof bad.item_id === "string") {
          await db.delete(STORE_ITEMS, bad.item_id);
        }
      } catch {
        // quarantine itself failed (storage full): keep the record in place.
      }
    }
    const storedNotice = await this._metaGet("notice");
    if (storedNotice && !this.notice) this.notice = storedNotice;
    return healthy;
  }

  /// One-time, non-destructive import of the legacy localStorage queue.
  /// * Array entries become queue items with fresh UUIDs (legacy id kept).
  /// * UPDATE_TREE entries are PRESERVED but held for manual review (D2).
  /// * Unparseable data is quarantined and the localStorage key is kept
  ///   untouched so nothing is lost.
  /// The legacy key is removed only after a read-back confirms every entry
  /// landed in IndexedDB (requirement 9).
  async importLegacyQueue() {
    const already = await this._metaGet("legacy_imported");
    if (already) return { imported: 0, skipped: false };

    let raw = null;
    try {
      raw = localStorage.getItem(LEGACY_QUEUE_KEY);
    } catch {
      raw = null;
    }
    if (raw === null || raw === undefined) {
      await this._metaSet("legacy_imported", true);
      return { imported: 0, skipped: false };
    }

    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch {
      // Preserve everything: quarantine a copy AND leave localStorage alone.
      await this.quarantineRecord(
        raw,
        "The legacy offline queue could not be parsed.",
      );
      await this._metaSet("legacy_imported", true); // never loop
      return { imported: 0, skipped: true, preserved: true };
    }
    if (!Array.isArray(parsed)) {
      await this.quarantineRecord(
        raw,
        "The legacy offline queue had an unrecognized shape.",
      );
      await this._metaSet("legacy_imported", true);
      return { imported: 0, skipped: true, preserved: true };
    }

    const now = new Date().toISOString();
    const imported = [];
    for (const entry of parsed) {
      if (!entry || typeof entry !== "object") continue;
      const isUpdate = entry.type === "UPDATE_TREE";
      imported.push({
        item_id: uuidFactory(),
        legacy_id: typeof entry.id === "number" ? entry.id : null,
        type: typeof entry.type === "string" ? entry.type : "CREATE_TREE",
        payload:
          entry.payload && typeof entry.payload === "object"
            ? { ...entry.payload }
            : {},
        hasPhoto: false, // legacy web queue never stored photo blobs
        verified: entry.verified === true,
        created_at: entry.timestamp || now,
        attempts: 0,
        last_error: isUpdate
          ? "Tree updates are not queued in G7. Review this entry and re-apply the change manually - nothing was deleted."
          : entry.last_error || null,
        last_error_kind: isUpdate ? "unknown" : entry.last_error_kind || null,
        requires_review: isUpdate ? true : entry.requires_review === true,
        next_retry_at_ms: null,
      });
    }

    const db = await this.open();
    const tx = db.transaction(STORE_ITEMS, "readwrite");
    for (const item of imported) await tx.store.put(item);
    await tx.done;

    // Read-back validation BEFORE touching the legacy data.
    const check = await db.getAll(STORE_ITEMS);
    const landed = imported.filter((item) =>
      check.some((row) => row.item_id === item.item_id),
    );
    if (landed.length !== imported.length || imported.length !== parsed.filter((e) => e && typeof e === "object").length) {
      // Something did not land: keep localStorage untouched for recovery.
      this._setNotice(
        "The legacy offline queue import could not be fully confirmed; the original localStorage copy was kept untouched.",
      );
      await this._metaSet("notice", this.notice);
      return { imported: landed.length, skipped: true, preserved: true };
    }

    try {
      localStorage.removeItem(LEGACY_QUEUE_KEY);
    } catch {
      /* storage unavailable: the confirmed copy in IDB is authoritative */
    }
    await this._metaSet("legacy_imported", true);
    return { imported: imported.length, skipped: false };
  }

  // ── Items ────────────────────────────────────────────────────────────────

  putItem(item) {
    return this._enqueueWrite(async () => {
      try {
        const db = await this.open();
        await db.put(STORE_ITEMS, item);
      } catch (error) {
        this._handleWriteError(error, "queue record");
        throw error;
      }
      return item;
    });
  }

  deleteItem(itemId) {
    return this._enqueueWrite(async () => {
      try {
        const db = await this.open();
        await db.delete(STORE_ITEMS, itemId);
      } catch (error) {
        this._handleWriteError(error, "queue record");
        throw error;
      }
    });
  }

  // ── Photos (Blob store) ──────────────────────────────────────────────────

  async getPhoto(itemId) {
    const db = await this.open();
    return db.get(STORE_PHOTOS, itemId);
  }

  putPhoto(itemId, blob) {
    return this._enqueueWrite(async () => {
      try {
        const db = await this.open();
        await db.put(STORE_PHOTOS, blob, itemId);
      } catch (error) {
        this._handleWriteError(error, "photo");
        throw error;
      }
    });
  }

  deletePhoto(itemId) {
    return this._enqueueWrite(async () => {
      try {
        const db = await this.open();
        await db.delete(STORE_PHOTOS, itemId);
      } catch (error) {
        this._handleWriteError(error, "photo");
        throw error;
      }
    });
  }

  _handleWriteError(error, what) {
    const quota =
      error &&
      (error.name === "QuotaExceededError" ||
        error.code === 22 ||
        /quota/i.test(error.message || ""));
    if (quota) {
      // Requirement 8: surface quota failures loudly; the record stays in
      // memory and the user is told it may not survive a reload.
      this._setNotice(
        `Browser storage is full: the ${what} could not be written to disk. Free up site storage (or reduce photo sizes) - unsaved records may not survive a reload.`,
      );
      this._metaSet("notice", this.notice).catch(() => {});
    } else {
      this._setNotice(
        `The ${what} could not be written to browser storage (${error?.message || "unknown error"}).`,
      );
      this._metaSet("notice", this.notice).catch(() => {});
    }
  }

  async clearNotice() {
    this.notice = null;
    try {
      const db = await this.open();
      await db.delete(STORE_META, "notice");
    } catch {
      /* ignore */
    }
  }
}

// ── Drafts helpers (shared by offline/drafts.js) ────────────────────────────

export async function draftGet(slot) {
  const db = await openDB(DB_NAME, DB_VERSION, { upgrade: upgradeDB });
  return db.get(STORE_DRAFTS, slot);
}

export async function draftPut(slot, value) {
  const db = await openDB(DB_NAME, DB_VERSION, { upgrade: upgradeDB });
  await db.put(STORE_DRAFTS, value, slot);
  // Confirm the copy before callers may discard anything (D5).
  const back = await db.get(STORE_DRAFTS, slot);
  if (JSON.stringify(back) !== JSON.stringify(value)) {
    throw new Error("draft read-back mismatch");
  }
}

export async function draftDelete(slot) {
  const db = await openDB(DB_NAME, DB_VERSION, { upgrade: upgradeDB });
  await db.delete(STORE_DRAFTS, slot);
}
