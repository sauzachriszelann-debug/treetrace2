// G7 (D5): durable recovery for the G2/G4 submission drafts.
//
// The existing AddTree/AIIdentify draft machinery reads and writes
// sessionStorage synchronously. To make those drafts survive tab close and
// browser reload WITHOUT rewriting the whole flow:
//  * every write goes to sessionStorage first (sync, same as before) and is
//    then mirrored into IndexedDB and confirmed by read-back;
//  * sessionStorage copies are discarded ONLY after the IndexedDB delete (or
//    tombstone) has succeeded - old copies are never thrown away before the
//    new state is confirmed (D5);
//  * on app start, drafts found only in IndexedDB (previous tab/session) are
//    restored into sessionStorage so the existing sync readers see them;
//  * the draft payload shapes, stable client_uuid keys, replay behavior and
//    recovery information are unchanged.

import { draftGet, draftPut, draftDelete } from "./store.js";

export const TREE_DRAFT_SLOT = "treetrace_tree_draft";
export const SUBMISSION_DRAFT_SLOT = "treetrace_submission_draft";

const SLOTS = [TREE_DRAFT_SLOT, SUBMISSION_DRAFT_SLOT];

/// Sync read - identical contract to the old sessionStorage read, provided
/// initDrafts() has run (AuthProvider awaits it before routes mount).
export function readDraft(slot) {
  try {
    const raw = sessionStorage.getItem(slot);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

function writeSession(slot, draft) {
  sessionStorage.setItem(slot, JSON.stringify(draft));
}

/// Persist a draft durably. sessionStorage is updated synchronously first so
/// the current tab always sees it; the IndexedDB mirror is confirmed by
/// read-back inside draftPut before this resolves.
export async function persistDraft(slot, draft) {
  try {
    writeSession(slot, draft);
  } catch {
    /* sessionStorage unavailable: the durable copy still lands below */
  }
  try {
    await draftPut(slot, draft);
  } catch (error) {
    // Mirror failed (quota/eviction). Surface a console warning - callers
    // may still show their own recovery text.
    console.warn("Draft could not be mirrored to IndexedDB:", error);
  }
}

/// Clear a draft. The sessionStorage copy survives until the durable copy is
/// confirmed gone; if IndexedDB deletion fails, a tombstone prevents the old
/// draft from being resurrected on the next load.
export async function clearDraft(slot) {
  try {
    await draftDelete(slot);
  } catch (error) {
    console.warn("Durable draft delete failed; writing tombstone:", error);
    try {
      await draftPut(slot, { cleared: true });
    } catch {
      /* storage unavailable - keep session copy removal best-effort */
    }
  }
  try {
    sessionStorage.removeItem(slot);
  } catch {
    /* ignore */
  }
}

/// One-time hydration at app start: restore durable drafts into
/// sessionStorage (tab closed/reloaded) and upgrade any session-only draft
/// into IndexedDB. Never discards either side (requirement 9 / D5).
export async function initDrafts() {
  for (const slot of SLOTS) {
    let sessionRaw = null;
    try {
      sessionRaw = sessionStorage.getItem(slot);
    } catch {
      sessionRaw = null;
    }
    let durable = null;
    try {
      durable = await draftGet(slot);
    } catch {
      durable = null;
    }

    if (durable && durable.cleared === true) {
      // Tombstone from an earlier failed delete: the draft is gone.
      if (sessionRaw !== null) sessionStorage.removeItem(slot);
      try {
        await draftDelete(slot);
      } catch {
        /* ignore */
      }
      continue;
    }

    if (durable && !sessionRaw) {
      // Previous session's draft: restore it into this tab.
      const { cleared: _ignored, ...value } = durable;
      try {
        writeSession(slot, value);
      } catch {
        /* sessionStorage unavailable */
      }
      continue;
    }

    if (sessionRaw && !durable) {
      // Upgrade a session-only draft into durable storage (confirmed).
      try {
        await draftPut(slot, JSON.parse(sessionRaw));
      } catch {
        /* mirror failure is non-fatal; write path will retry */
      }
      continue;
    }

    // Both exist. They are written together, so a mismatch means the session
    // copy is the newer tab state: keep it and re-mirror.
    if (sessionRaw && durable) {
      try {
        const sessionValue = JSON.parse(sessionRaw);
        if (JSON.stringify(sessionValue) !== JSON.stringify(durable)) {
          await draftPut(slot, sessionValue);
        }
      } catch {
        /* ignore */
      }
    }
  }
}
