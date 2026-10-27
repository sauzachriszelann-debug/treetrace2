// G7 sync engine - a direct port of G6's mobile OfflineQueueService
// (mobile/lib/services/offline_queue.dart) so web and mobile behave the same:
//  * D3: only PREVIOUSLY VERIFIED items ever upload; unverified items wait;
//  * bounded automatic retries with exponential backoff (30s doubling,
//    capped at 30 minutes, max 5 auto attempts);
//  * permanent decisions (403/409/4xx validation) are held for review and
//    NEVER retried automatically;
//  * uncertain outcomes of NON-idempotent types are held for review (D2/req 6)
//    instead of being blindly replayed;
//  * photo-first: the record is never created without its required upload,
//    and the photo Blob is only discarded after upload AND the server
//    operation both succeeded (D5).

import { uuidFactory } from "./store.js";

export const QueueFailureKind = {
  network: "network", // provably not delivered
  ambiguous: "ambiguous", // non-idempotent, outcome uncertain
  auth: "auth", // 401
  quota: "quota", // 402
  role: "role", // 403
  conflict: "conflict", // 409 - permanent, never auto-retried
  validation: "validation", // 400/404/422
  server: "server", // 5xx
  missingPhoto: "missing_photo",
  retriesExhausted: "retries_exhausted",
  unknown: "unknown",
};

/// Kinds a human must resolve before any sync (automatic or one-tap) may
/// touch the item again. Explicit per-item "Retry" clears the flag.
export const reviewKinds = new Set([
  QueueFailureKind.ambiguous,
  QueueFailureKind.role,
  QueueFailureKind.conflict,
  QueueFailureKind.validation,
  QueueFailureKind.missingPhoto,
  QueueFailureKind.retriesExhausted,
  QueueFailureKind.unknown,
]);

/// Queue types whose server endpoints are idempotent through client_uuid
/// (G2 trees, G4 tree-submissions): an uncertain outcome is always safe to
/// retry automatically because a replay cannot duplicate the record.
export const idempotentQueueTypes = new Set([
  "CREATE_TREE",
  "CREATE_TREE_SUBMISSION",
]);

/// Queue types allowed in G7 (D2). UPDATE_TREE is deliberately absent:
/// PATCH has no idempotency key, so updates are never auto-queued.
export const supportedQueueTypes = new Set([
  "CREATE_TREE",
  "CREATE_TREE_SUBMISSION",
  "CREATE_HEALTH_LOG",
  "SUBMIT_UNKNOWN",
  "CREATE_PLANTING_RECOMMENDATION",
]);

/// Automatic sync attempts per item before it is held for review (D3).
export const maxAutoAttempts = 5;

export function photoPurposeFor(type) {
  switch (type) {
    case "CREATE_TREE":
      // Staff-only upload purpose; only staff may create CREATE_TREE items.
      return "tree_photo";
    case "CREATE_TREE_SUBMISSION":
      // Citizens may not upload purpose=tree_photo (backend role gate), the
      // same rule G6 applies on mobile.
      return "unknown_species";
    case "SUBMIT_UNKNOWN":
      return "unknown_species";
    case "CREATE_PLANTING_RECOMMENDATION":
      return "planting_submission";
    default:
      return "unknown_species";
  }
}

function serverDetail(error) {
  const data = error?.response?.data;
  if (data && typeof data === "object" && data.detail !== null) {
    if (typeof data.detail === "object" && data.detail.message) {
      return String(data.detail.message);
    }
    if (typeof data.detail === "string") return data.detail;
    if (Array.isArray(data.detail)) {
      return data.detail
        .map((d) => (typeof d === "string" ? d : d?.msg || JSON.stringify(d)))
        .join(" ");
    }
  }
  return null;
}

/// Pure classifier: axios failure -> disposition (D3/req 6 rules).
///
/// `online` is navigator.onLine at classification time: a request issued
/// while the browser reports no connectivity is treated as provably
/// undelivered (safe retry for every type). When the browser claims to be
/// online but no response arrived, delivery is UNKNOWN: idempotent types
/// retry safely via client_uuid; non-idempotent types become AMBIGUOUS and
/// are held for review. G7 does NOT claim exactly-once delivery for
/// non-idempotent operations (D7).
export function classifyFailure(error, { idempotent, online }) {
  if (!error || !error.response) {
    // No HTTP response: transport-level failure.
    if (online === false) {
      return {
        kind: QueueFailureKind.network,
        requiresReview: false,
        retryable: true,
        abortRun: true,
        message: "Could not reach the server - the request was not sent.",
      };
    }
    if (idempotent) {
      return {
        kind: QueueFailureKind.network,
        requiresReview: false,
        retryable: true,
        abortRun: false,
        message:
          "Connection lost before the response arrived. Safe to retry: " +
          "this record uses an idempotency key.",
      };
    }
    return {
      kind: QueueFailureKind.ambiguous,
      requiresReview: true,
      retryable: false,
      abortRun: false,
      message:
        "The request may have already reached the server. Kept for review " +
        "and NOT retried automatically, because this record type has no " +
        "idempotency key and a blind retry could create a duplicate.",
    };
  }

  const status = error.response.status ?? 0;
  const detail = serverDetail(error);
  if (status === 401) {
    return {
      kind: QueueFailureKind.auth,
      requiresReview: false,
      retryable: false,
      abortRun: true,
      message: detail ?? "Session expired. Sign in again to resume sync.",
    };
  }
  if (status === 402) {
    return {
      kind: QueueFailureKind.quota,
      requiresReview: false,
      retryable: true,
      abortRun: false,
      message: detail ?? "Daily quota reached for this plan.",
    };
  }
  if (status === 403) {
    return {
      kind: QueueFailureKind.role,
      requiresReview: true,
      retryable: false,
      abortRun: false,
      message:
        detail ?? "This account role is not allowed to perform the operation.",
    };
  }
  if (status === 409) {
    return {
      kind: QueueFailureKind.conflict,
      requiresReview: true,
      retryable: false,
      abortRun: false,
      message:
        detail ??
        "Conflicts with an existing record. Nothing was merged or overwritten.",
    };
  }
  if (status === 400 || status === 404 || status === 422) {
    return {
      kind: QueueFailureKind.validation,
      requiresReview: true,
      retryable: false,
      abortRun: false,
      message: detail ?? `The server rejected this record (HTTP ${status}).`,
    };
  }
  if (status >= 500) {
    return {
      kind: QueueFailureKind.server,
      requiresReview: false,
      retryable: true,
      abortRun: false,
      message: detail ?? `Server error (HTTP ${status}). Will be retried.`,
    };
  }
  return {
    kind: QueueFailureKind.unknown,
    requiresReview: true,
    retryable: false,
    abortRun: false,
    message: detail ?? `Unexpected response (HTTP ${status}); held for review.`,
  };
}

export function backoffMs(attempts) {
  // 30s, 60s, 120s, ... capped at 30 minutes.
  const exponent = Math.min(Math.max(attempts - 1, 0), 20);
  const ms = 30000 * 2 ** exponent;
  return ms > 1800000 ? 1800000 : ms;
}

export const SyncResult = {
  notRun: { ran: false, alreadyRunning: false, offline: false, synced: 0, heldForReview: 0, keptForRetry: 0, skippedUnverified: 0, skippedBackoff: 0, authError: null },
  offlineResult: { ran: false, alreadyRunning: false, offline: true, synced: 0, heldForReview: 0, keptForRetry: 0, skippedUnverified: 0, skippedBackoff: 0, authError: null },
};

export function emptyResult(overrides = {}) {
  return {
    ran: false,
    alreadyRunning: false,
    offline: false,
    synced: 0,
    heldForReview: 0,
    keptForRetry: 0,
    skippedUnverified: 0,
    skippedBackoff: 0,
    authError: null,
    ...overrides,
  };
}

export class OfflineQueueService {
  /**
   * @param {object} deps
   * @param {import('./store.js').QueueStore} deps.store
   * @param {() => Promise<boolean>} deps.isOnline
   * @param {(type: string, payload: object) => Promise<any>} deps.sender
   * @param {(blob: Blob, purpose: string) => Promise<string|null>} deps.uploader
   * @param {() => number} [deps.clock] epoch ms (test seam)
   * @param {() => string} [deps.idFactory]
   */
  constructor({ store, isOnline, sender, uploader, clock, idFactory }) {
    this.store = store;
    this._isOnline = isOnline ?? (async () => true);
    this._sender = sender ?? null;
    this._uploader = uploader ?? null;
    this._clock = clock ?? (() => Date.now());
    this._idFactory = idFactory;
    this._items = [];
    this._loaded = false;
    this._syncing = false;
  }

  get syncInFlight() {
    return this._syncing;
  }

  get corruptionNotice() {
    return this.store.notice;
  }

  async load() {
    if (this._loaded) return;
    await this.store.open();
    await this.store.importLegacyQueue();
    this._items = await this.store.loadItems();
    this._loaded = true;
  }

  async all() {
    await this.load();
    return [...this._items];
  }

  async count() {
    return (await this.all()).length;
  }

  _newId() {
    if (this._idFactory) return this._idFactory();
    return uuidFactory();
  }

  async enqueue(type, payload, { photoBlob = null, requiresReview = false, reviewReason = null } = {}) {
    await this.load();
    const item = {
      item_id: this._newId(),
      legacy_id: null,
      type,
      payload: { ...payload },
      hasPhoto: Boolean(photoBlob),
      verified: false,
      created_at: new Date(this._clock()).toISOString(),
      attempts: 0,
      last_error: reviewReason ?? null,
      last_error_kind: requiresReview ? QueueFailureKind.ambiguous : null,
      requires_review: Boolean(requiresReview),
      next_retry_at_ms: null,
    };
    if (photoBlob) {
      await this.store.putPhoto(item.item_id, photoBlob);
    }
    this._items.push(item);
    try {
      await this.store.putItem(item);
    } catch (error) {
      // Write failed (quota): keep the in-memory record and surface the
      // store notice; never silently drop it.
      this.store._handleWriteError?.(error, "queue record");
    }
    return item;
  }

  async setVerified(itemId, verified) {
    await this.load();
    for (const item of this._items) {
      if (item.item_id === itemId) item.verified = verified;
    }
    const item = this._items.find((i) => i.item_id === itemId);
    if (item) await this.store.putItem(item);
  }

  async verifyAll() {
    await this.load();
    for (const item of this._items) item.verified = true;
    await this._persistAll();
  }

  async remove(itemId) {
    await this.load();
    const before = this._items.length;
    this._items = this._items.filter((i) => i.item_id !== itemId);
    if (this._items.length !== before) {
      await this.store.deleteItem(itemId);
      await this.store.deletePhoto(itemId);
    }
  }

  /// Explicit per-item retry after review: clears the hold and backoff so a
  /// manual sync may try exactly what the user asked for.
  async resolveForManualRetry(itemId) {
    await this.load();
    for (const item of this._items) {
      if (item.item_id === itemId) {
        item.requires_review = false;
        item.attempts = 0;
        item.next_retry_at_ms = null;
        item.last_error = null;
        item.last_error_kind = null;
      }
    }
    const item = this._items.find((i) => i.item_id === itemId);
    if (item) await this.store.putItem(item);
  }

  /// Explicit user consent to sync WITHOUT a missing photo blob (D5: record
  /// or photo are never dropped without this kind of decision).
  async continueWithoutPhoto(itemId) {
    await this.load();
    for (const item of this._items) {
      if (item.item_id === itemId) {
        item.hasPhoto = false;
        item.requires_review = false;
        item.attempts = 0;
        item.next_retry_at_ms = null;
        item.last_error = null;
        item.last_error_kind = null;
        await this.store.deletePhoto(item.item_id);
        await this.store.putItem(item);
      }
    }
  }

  async _persistAll() {
    for (const item of this._items) {
      try {
        await this.store.putItem(item);
      } catch {
        /* store notice already surfaced */
      }
    }
  }

  // ── Sync engine (G6 parity) ──────────────────────────────────────────────

  async sync({ auto }) {
    if (this._syncing) return emptyResult({ alreadyRunning: true });
    await this.load();
    if (!this._sender) return SyncResult.notRun;
    const online = await this._isOnline();
    if (!online) return SyncResult.offlineResult;

    this._syncing = true;
    let synced = 0;
    let heldForReview = 0;
    let keptForRetry = 0;
    let skippedUnverified = 0;
    let skippedBackoff = 0;
    let authError = null;

    try {
      const nowMs = this._clock();
      for (const item of [...this._items]) {
        // D3 / safeguard: unverified records are NEVER uploaded, either mode.
        if (!item.verified) {
          skippedUnverified++;
          continue;
        }
        // Held records are skipped by BOTH modes: only the explicit per-item
        // retry clears them (permanent conflicts never retried automatically).
        if (item.requires_review) {
          heldForReview++;
          continue;
        }
        if (auto) {
          if (item.attempts >= maxAutoAttempts) {
            this._hold(
              item,
              QueueFailureKind.retriesExhausted,
              `Automatic retries paused after ${maxAutoAttempts} attempts. Review this record and retry manually or remove it.`,
            );
            heldForReview++;
            await this.store.putItem(item);
            continue;
          }
          const nextAt = item.next_retry_at_ms;
          if (nextAt !== null && nextAt > nowMs) {
            skippedBackoff++;
            continue;
          }
        }

        // ── Photo first (D5): never create the record without the required
        // upload; never discard the photo unless both steps succeeded. ──
        if (item.hasPhoto && !item.payload.photo_url) {
          let blob = null;
          try {
            blob = await this.store.getPhoto(item.item_id);
          } catch {
            blob = null;
          }
          if (!blob) {
            this._hold(
              item,
              QueueFailureKind.missingPhoto,
              "The photo for this record is missing from browser storage. Continue without the photo or remove the record.",
            );
            heldForReview++;
            await this.store.putItem(item);
            continue;
          }
          let url;
          try {
            if (!this._uploader) {
              throw new Error("photo uploader unavailable");
            }
            url = await this._uploader(blob, photoPurposeFor(item.type));
            if (!url || !String(url).trim()) {
              throw new Error("photo upload returned no URL");
            }
          } catch (error) {
            // Re-upload is harmless (a fresh object each time): idempotent.
            const info = classifyFailure(error, {
              idempotent: true,
              online,
            });
            item.attempts++;
            item.last_error_kind = info.kind;
            item.last_error = `Photo upload failed: ${info.message}`;
            if (info.requiresReview) {
              this._hold(item, info.kind, item.last_error);
              heldForReview++;
            } else {
              item.next_retry_at_ms =
                this._clock() + backoffMs(item.attempts);
              keptForRetry++;
            }
            await this.store.putItem(item);
            if (info.kind === QueueFailureKind.network && info.abortRun) {
              break;
            }
            continue; // photo failed => the record is NOT created (D5)
          }
          item.payload = { ...item.payload, photo_url: url };
          await this.store.putItem(item); // crash-safe: skip re-upload later
        }

        try {
          const payload = { ...item.payload };
          if (item.type === "CREATE_TREE_SUBMISSION") {
            payload.source = payload.source ?? "mobile";
          }
          await this._sender(item.type, payload);
          // Confirmed: photo upload (if any) AND server operation both
          // succeeded - only now is the item (and its photo) removed.
          this._items = this._items.filter((i) => i.item_id !== item.item_id);
          synced++;
          await this.store.deleteItem(item.item_id);
          if (item.hasPhoto) await this.store.deletePhoto(item.item_id);
        } catch (error) {
          const info = classifyFailure(error, {
            idempotent: idempotentQueueTypes.has(item.type),
            online,
          });
          item.attempts++;
          item.last_error_kind = info.kind;
          item.last_error = info.message;
          if (info.requiresReview) {
            this._hold(item, info.kind, info.message);
            heldForReview++;
          } else {
            item.next_retry_at_ms = this._clock() + backoffMs(item.attempts);
            keptForRetry++;
          }
          await this.store.putItem(item);
          if (info.kind === QueueFailureKind.auth) {
            authError = info.message;
            break;
          }
          if (info.kind === QueueFailureKind.network && info.abortRun) {
            break;
          }
        }
      }
    } finally {
      this._syncing = false;
    }

    return emptyResult({
      ran: true,
      synced,
      heldForReview,
      keptForRetry,
      skippedUnverified,
      skippedBackoff,
      authError,
    });
  }

  _hold(item, kind, message) {
    item.requires_review = true;
    item.last_error_kind = kind;
    item.last_error = message;
  }
}
