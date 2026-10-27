// G7 (D8): Field Sync Review - full parity with G6's mobile screen.
//
// Shows per-item verification state, review holds with their exact reason,
// last error + attempts, missing-photo warnings with an explicit escape
// hatch, quota/auth/conflict outcomes from the last run, corruption and
// storage-quota notices, and an honest statement of the browser's storage
// eviction limits (no guaranteed-delivery promises).

import { useEffect, useState } from "react";
import { useOfflineSyncStore } from "@/offline/OfflineSyncProvider";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Checkbox } from "@/components/ui/checkbox";
import {
  AlertTriangle,
  Camera,
  CloudOff,
  CloudUpload,
  ImageOff,
  Info,
  Loader2,
  Lock,
  RefreshCw,
  Trash2,
} from "lucide-react";

const TYPE_LABELS = {
  CREATE_TREE: "Tree inventory",
  CREATE_TREE_SUBMISSION: "Tree submission (pending approval)",
  CREATE_HEALTH_LOG: "Health log",
  SUBMIT_UNKNOWN: "Unknown species review",
  CREATE_PLANTING_RECOMMENDATION: "Planting suggestion",
  UPDATE_TREE: "Tree update",
};

const REVIEW_LABELS = {
  ambiguous: "Possible duplicate - review",
  conflict: "Conflicts with a record",
  validation: "Server rejected this record",
  role: "Not allowed for this account",
  missing_photo: "Photo missing on device",
  retries_exhausted: "Automatic retries paused",
  unknown: "Needs review",
};

export default function FieldSync() {
  const {
    ready,
    isOnline,
    queue,
    syncing,
    result,
    notice,
    autoSyncAvailable,
    setVerified,
    verifyAll,
    remove,
    retryOnce,
    continueWithoutPhoto,
    syncNow,
    dismissNotice,
    getPhoto,
  } = useOfflineSyncStore();

  const verified = queue.filter((i) => i.verified).length;
  const needsReview = queue.filter((i) => i.requires_review).length;
  const syncable = queue.filter((i) => i.verified && !i.requires_review).length;
  const canSync = syncable > 0 && !syncing && isOnline;

  return (
    <div className="p-4 sm:p-6 lg:p-8">
      <div className="mb-6 flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h1 className="font-fraunces text-2xl font-semibold sm:text-3xl">Field Sync Review</h1>
          <p className="mt-1 text-muted-foreground">Review offline web records before uploading them to the server.</p>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={verifyAll} disabled={queue.length === 0 || syncing}>
            Verify All
          </Button>
          <Button onClick={() => syncNow({ auto: false })} disabled={!canSync}>
            {syncing ? (
              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
            ) : (
              <CloudUpload className="mr-2 h-4 w-4" />
            )}
            {syncing ? "Syncing" : "Sync Verified"}
          </Button>
        </div>
      </div>

      {!isOnline && (
        <NoticePanel tone="warn" icon={<CloudOff className="h-4 w-4" />}>
          {autoSyncAvailable
            ? "Offline. Verified records wait here and sync automatically when the connection returns."
            : "Offline. Verified records wait here for manual sync when the connection returns."}
        </NoticePanel>
      )}

      {!autoSyncAvailable && (
        <NoticePanel tone="warn" icon={<Lock className="h-4 w-4" />}>
          Automatic sync is disabled in this browser because cross-tab locking (Web Locks)
          is unavailable, so background sync could race between tabs. Use Sync Verified
          manually - only one sync runs at a time, and records that lack an idempotency
          key are never retried for you.
        </NoticePanel>
      )}

      {notice && (
        <NoticePanel
          tone="error"
          icon={<AlertTriangle className="h-4 w-4" />}
          onDismiss={dismissNotice}
        >
          {notice}
        </NoticePanel>
      )}

      {result && <ResultBanner result={result} />}

      <Card className="mb-5">
        <CardContent className="space-y-2 p-4">
          <div className="flex flex-wrap items-center gap-3">
            <Badge variant="outline">{queue.length} pending</Badge>
            <Badge>{verified} verified</Badge>
            {needsReview > 0 && (
              <Badge variant="destructive">{needsReview} need review</Badge>
            )}
            <p className="text-sm text-muted-foreground">
              Only verified items will sync. Items marked &quot;needs review&quot; are never
              retried automatically.
            </p>
          </div>
          <p className="text-xs text-muted-foreground">
            Records and photos are stored in this browser (IndexedDB). Browsers may evict
            site data under storage pressure or when site data is cleared - sync promptly.
            A record is only confirmed sent when it leaves this list.
          </p>
        </CardContent>
      </Card>

      {!ready ? (
        <Card>
          <CardContent className="flex items-center gap-2 p-10 text-muted-foreground">
            <Loader2 className="h-4 w-4 animate-spin" /> Loading offline records…
          </CardContent>
        </Card>
      ) : queue.length === 0 ? (
        <Card>
          <CardContent className="p-10 text-center text-muted-foreground">
            No offline records waiting for review.
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-4 lg:grid-cols-2">
          {queue.map((item) => (
            <QueueCard
              key={item.item_id}
              item={item}
              getPhoto={getPhoto}
              onVerified={(v) => setVerified(item.item_id, v)}
              onRemove={() => remove(item.item_id)}
              onRetry={() => retryOnce(item.item_id)}
              onContinueWithoutPhoto={() => continueWithoutPhoto(item.item_id)}
            />
          ))}
        </div>
      )}
    </div>
  );
}

function NoticePanel({ tone, icon, children, onDismiss }) {
  const styles =
    tone === "error"
      ? "border-red-300 bg-red-50 text-red-900"
      : tone === "auth"
        ? "border-red-300 bg-red-50 text-red-900"
        : "border-amber-300 bg-amber-50 text-amber-900";
  return (
    <div className={`mb-4 flex items-start gap-3 rounded-xl border p-4 text-sm ${styles}`}>
      <span className="mt-0.5">{icon}</span>
      <div className="flex-1 whitespace-pre-wrap">{children}</div>
      {onDismiss && (
        <Button variant="ghost" size="sm" onClick={onDismiss}>
          Dismiss
        </Button>
      )}
    </div>
  );
}

function ResultBanner({ result }) {
  if (result.authError) {
    return (
      <NoticePanel tone="auth" icon={<Lock className="h-4 w-4" />}>
        Session expired - sign in again to resume sync. All queued records and photos are
        kept on this device. ({result.authError})
      </NoticePanel>
    );
  }
  if (result.alreadyRunning || (!result.ran && !result.offline)) return null;
  const parts = [];
  if (result.offline) parts.push("Offline - nothing was sent.");
  if (result.ran) parts.push(`Synced ${result.synced}.`);
  if (result.keptForRetry > 0)
    parts.push(`${result.keptForRetry} waiting to retry (temporary problem).`);
  if (result.heldForReview > 0)
    parts.push(`${result.heldForReview} held for your review - never retried automatically.`);
  if (result.skippedUnverified > 0)
    parts.push(`${result.skippedUnverified} skipped: not verified yet.`);
  if (result.skippedBackoff > 0)
    parts.push(`${result.skippedBackoff} in backoff after repeated failures.`);
  if (parts.length === 0) return null;
  return (
    <NoticePanel
      tone={result.heldForReview > 0 ? "warn" : "info"}
      icon={<Info className="h-4 w-4" />}
    >
      {parts.join(" ")}
    </NoticePanel>
  );
}

function QueueCard({
  item,
  getPhoto,
  onVerified,
  onRemove,
  onRetry,
  onContinueWithoutPhoto,
}) {
  const reviewLabel = item.requires_review
    ? REVIEW_LABELS[item.last_error_kind] || "Needs review"
    : null;
  const photoMissing =
    item.hasPhoto && !item.payload?.photo_url && item.last_error_kind === "missing_photo";

  return (
    <Card
      className={
        item.requires_review
          ? "border-red-300"
          : item.verified
            ? "border-emerald-300"
            : ""
      }
    >
      <CardHeader className="flex flex-row items-start justify-between gap-3">
        <div>
          <CardTitle className="text-base">{titleFor(item)}</CardTitle>
          <p className="text-xs text-muted-foreground">
            {TYPE_LABELS[item.type] || "Offline record"} · {formatDate(item.created_at)}
          </p>
        </div>
        <Checkbox checked={item.verified} onCheckedChange={(v) => onVerified(Boolean(v))} />
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="flex gap-3">
          <PhotoThumb getPhoto={getPhoto} item={item} />
          <div className="min-w-0 flex-1 rounded-lg border bg-muted/30 p-3 text-sm">
            {payloadRows(item.payload).length === 0 ? (
              <span className="text-muted-foreground">No field values</span>
            ) : (
              payloadRows(item.payload).map(([key, value]) => (
                <div key={key} className="grid grid-cols-[130px_1fr] gap-2 py-0.5">
                  <span className="font-medium text-muted-foreground">{prettyKey(key)}</span>
                  <span className="truncate">{String(value ?? "")}</span>
                </div>
              ))
            )}
          </div>
        </div>

        {reviewLabel && (
          <div className="rounded-lg border border-red-300 bg-red-50 p-3 text-xs text-red-900">
            <span className="font-semibold">{reviewLabel}.</span>{" "}
            {item.last_error || ""}
          </div>
        )}
        {!reviewLabel && item.last_error && item.attempts > 0 && (
          <p className="text-xs text-muted-foreground">
            Last error: {item.last_error} (attempt {item.attempts})
          </p>
        )}
        {photoMissing && (
          <div className="rounded-lg border border-amber-300 bg-amber-50 p-3 text-xs text-amber-900">
            The photo for this record is missing from browser storage. It will not upload
            until you continue without it or remove the record.
          </div>
        )}

        <div className="flex items-center justify-between gap-2">
          <span
            className={
              item.verified
                ? item.requires_review
                  ? "text-sm font-medium text-red-600"
                  : "text-sm font-medium text-emerald-600"
                : "text-sm font-medium text-amber-600"
            }
          >
            {item.verified
              ? item.requires_review
                ? "Verified - held for review"
                : "Verified for sync"
              : "Needs your verification"}
          </span>
          <div className="flex items-center gap-1">
            {item.requires_review && item.verified && (
              <Button variant="outline" size="sm" onClick={onRetry}>
                <RefreshCw className="mr-1 h-3.5 w-3.5" /> Retry once
              </Button>
            )}
            {item.last_error_kind === "missing_photo" && (
              <Button variant="outline" size="sm" onClick={onContinueWithoutPhoto}>
                <ImageOff className="mr-1 h-3.5 w-3.5" /> Sync w/o photo
              </Button>
            )}
            <Button
              variant="ghost"
              size="sm"
              className="text-destructive hover:text-destructive"
              onClick={onRemove}
            >
              <Trash2 className="mr-1 h-3.5 w-3.5" /> Remove
            </Button>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}

function PhotoThumb({ getPhoto, item }) {
  const [url, setUrl] = useState(null);
  useEffect(() => {
    let objectUrl = null;
    let cancelled = false;
    if (item.hasPhoto) {
      getPhoto(item.item_id).then((blob) => {
        if (blob && !cancelled) {
          objectUrl = URL.createObjectURL(blob);
          setUrl(objectUrl);
        }
      });
    }
    return () => {
      cancelled = true;
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [item.item_id, item.hasPhoto, getPhoto]);

  return (
    <div className="flex h-14 w-14 flex-shrink-0 items-center justify-center overflow-hidden rounded-lg border bg-primary/5">
      {url ? (
        <img src={url} alt="" className="h-full w-full object-cover" />
      ) : item.hasPhoto ? (
        <Camera className="h-5 w-5 text-primary/70" />
      ) : (
        <CloudUpload className="h-5 w-5 text-muted-foreground" />
      )}
    </div>
  );
}

function payloadRows(payload) {
  return Object.entries(payload || {})
    .filter(([, value]) => value !== null && value !== undefined && String(value).trim() !== "")
    .slice(0, 6);
}

function titleFor(item) {
  const payload = item.payload || {};
  return (
    payload.common_name ||
    payload.species_name ||
    payload.possible_name ||
    payload.scientific_name ||
    "Offline record"
  );
}

function formatDate(iso) {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleString();
}

function prettyKey(key) {
  return key
    .replaceAll("_", " ")
    .replace(/\b\w/g, (m) => m.toUpperCase());
}
