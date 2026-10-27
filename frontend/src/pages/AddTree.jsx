import { useState } from "react";
import { useNavigate, Link } from "react-router-dom";
import { useQueryClient } from "@tanstack/react-query";
import { treesApi } from "@/api/trees";
import TreeForm from "@/components/trees/TreeForm";
import { Button } from "@/components/ui/button";
import { ArrowLeft } from "lucide-react";
import { toast } from "sonner";
import { useAuth } from "@/lib/AuthContext";
import { useOfflineSyncStore } from "@/offline/OfflineSyncProvider";
import {
  readDraft as readDraftSlot,
  persistDraft,
  clearDraft as clearDraftSlot,
  TREE_DRAFT_SLOT,
} from "@/offline/drafts";

// Local wrappers keep the original sync call-site contract while the durable
// module mirrors every write into IndexedDB (G7 D5).
const readDraft = () => readDraftSlot(TREE_DRAFT_SLOT);
const writeDraft = (draft) => {
  void persistDraft(TREE_DRAFT_SLOT, draft);
};
const clearDraft = () => {
  void clearDraftSlot(TREE_DRAFT_SLOT);
};

const normalizeName = (value) => (value || "").toString().trim().toLowerCase();
const normalizeCoord = (value) => {
  if (value === "" || value === null || value === undefined) return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.round(parsed * 1e7) / 1e7 : null;
};
const identityOf = (data) =>
  [
    normalizeName(data.common_name),
    normalizeName(data.scientific_name),
    normalizeCoord(data.lat),
    normalizeCoord(data.lng),
    normalizeName(data.barangay),
  ].join("|");

const generateSubmissionKey = () => {
  if (typeof crypto !== "undefined" && crypto.randomUUID) {
    return crypto.randomUUID();
  }
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
};

export default function AddTree() {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const [loading, setLoading] = useState(false);
  const [draft, setDraft] = useState(readDraft);
  const [formInitial, setFormInitial] = useState({});
  const [formKey, setFormKey] = useState(0);
  const [replayInfo, setReplayInfo] = useState(null);
  const [conflict, setConflict] = useState(null);
  const [pendingReplacement, setPendingReplacement] = useState(null);
  // G3 nearby matching: advisory duplicate prevention before NEW submissions.
  const [nearbyCandidates, setNearbyCandidates] = useState(null);
  const [nearbyError, setNearbyError] = useState(false);
  const [nearbyPendingData, setNearbyPendingData] = useState(null);
  const { user } = useAuth();
  const { enqueue } = useOfflineSyncStore();

  if (user?.role === "citizen") {
    return (
      <div className="p-8 max-w-2xl mx-auto">
        <Link
          to="/ai-identify"
          className="inline-flex items-center gap-2 text-muted-foreground hover:text-foreground text-sm mb-6 transition-colors"
        >
          <ArrowLeft className="w-4 h-4" />
          Back to AI Identify
        </Link>

        <div className="bg-card border border-border rounded-xl p-6 shadow-sm">
          <h1 className="font-fraunces text-3xl font-semibold">Official Inventory Restricted</h1>
          <p className="text-muted-foreground mt-3">
            Citizen accounts cannot add official inventory trees directly.
            Please use AI Identify and submit the species for expert review.
            Admins or field workers will verify approved records.
          </p>
          <div className="mt-6 flex flex-wrap gap-3">
            <Button onClick={() => navigate("/ai-identify")}>
              Submit Through AI Identify
            </Button>
            <Button variant="outline" onClick={() => navigate("/my-submissions")}>
              View My Submissions
            </Button>
          </div>
        </div>
      </div>
    );
  }

  const resumeDraft = () => {
    if (!draft) return;
    setFormInitial(draft.snapshot || {});
    setFormKey((key) => key + 1);
    toast.info(
      "Draft restored. Saving sends an edited submission under the same key; the original payload stays retryable.",
    );
  };

  const discardDraft = () => {
    clearDraft();
    setDraft(null);
    toast.success("Recovered draft discarded.");
  };

  const performSubmit = async (
    data,
    draftMeta,
    { preserveSnapshot = false, photoFile = null } = {},
  ) => {
    // G7: fully offline - nothing was sent, so the queue owns the payload
    // and the photo Blob under the same stable client_uuid (G2).
    if (!navigator.onLine) {
      const key = draftMeta?.key || generateSubmissionKey();
      try {
        await enqueue(
          "CREATE_TREE",
          { ...data, client_uuid: key },
          { photoBlob: photoFile },
        );
        clearDraft();
        setDraft(null);
        setPendingReplacement(null);
        toast.success(
          "Saved offline. Review it in Field Sync - only verified records upload.",
        );
        navigate("/field-sync");
      } catch (error) {
        toast.error(
          `Could not save offline: ${error?.message || "browser storage unavailable"}. Nothing was sent.`,
        );
      }
      return;
    }
    setLoading(true);
    // Captured for the catch clause below (block-scoped to try is invisible
    // there): is there an earlier submission for this key that may exist on
    // the server?
    const hadPriorAttempt = Boolean(draftMeta?.original_payload);
    // Hoisted so the failure path can enqueue under the SAME key (G7 D5).
    const key = draftMeta?.key || generateSubmissionKey();
    try {
      // Persist the pending submission BEFORE the request: if it reaches the
      // server and the response is lost, the retry carries the same key.
      // original_payload is written ONCE per key - the first payload that may
      // have reached the server. An explicit edited Save reuses the same key
      // but never replaces it, so Retry Original always stays possible.
      writeDraft({
        key,
        created_at: draftMeta?.created_at || new Date().toISOString(),
        status: "in_flight",
        snapshot:
          preserveSnapshot && draftMeta?.snapshot ? draftMeta.snapshot : data,
        original_payload: draftMeta?.original_payload || data,
      });
      setDraft(readDraft());

      const response = await treesApi.create({ ...data, client_uuid: key });

      if (response?.idempotent_replay) {
        clearDraft();
        setDraft(null);
        qc.invalidateQueries({ queryKey: ["trees"] });
        const differences = response.replayed_differences || {};
        if (Object.keys(differences).length > 0) {
          setReplayInfo({ treeId: response.id, differences });
          toast.info(
            "This tree was already recorded; differences are shown below. Nothing was overwritten."
          );
        } else {
          toast.success(
            `Already recorded as tree #${response.id} - no duplicate was created.`
          );
          navigate(`/trees/${response.id}`);
        }
        return;
      }

      clearDraft();
      setDraft(null);
      qc.invalidateQueries({ queryKey: ["trees"] });
      toast.success("Tree record created successfully!");
      navigate(`/trees/${response.id}`);
    } catch (error) {
      const status = error?.response?.status;
      const current = readDraft();
      if (status === 409) {
        // The key belongs to a different tree. Nothing was merged.
        if (current) writeDraft({ ...current, status: "conflict" });
        setConflict({
          treeId: error.response.data?.detail?.existing_tree_id ?? null,
        });
      } else if (status === 422) {
        if (current) {
          const next = { ...current, status: "draft", snapshot: data };
          // A 422 definitively rejects THIS request before any insert, so
          // its sent copy is dropped - unless an earlier submission for the
          // same key is still unresolved and must stay retryable.
          if (!hadPriorAttempt) delete next.original_payload;
          writeDraft(next);
        }
        const detail = error?.response?.data?.detail;
        toast.error(
          typeof detail === "string"
            ? detail
            : "Please correct the highlighted fields and save again."
        );
      } else {
        // Network failure or server error: the request MAY have reached the
        // server. Keep the key and payload for a safe retry.
        if (photoFile) {
          // A photo is attached: park the whole submission (payload + Blob)
          // in the durable queue under the SAME key. CREATE_TREE is
          // idempotent, so a later replay cannot duplicate it - and the photo
          // survives a tab close (G7 D5).
          try {
            await enqueue(
              "CREATE_TREE",
              { ...data, client_uuid: draftMeta?.key || key },
              { photoBlob: photoFile },
            );
            clearDraft();
            setDraft(null);
            toast.error(
              "Connection problem - your submission with its photo is saved offline. Sync from Field Sync; retrying cannot create a duplicate.",
            );
            navigate("/field-sync");
            return;
          } catch {
            /* fall through to the draft path below */
          }
        }
        if (current) writeDraft({ ...current, status: "uncertain" });
        setDraft(readDraft());
        toast.error(
          "Connection problem - your submission is saved. Retrying will not create a duplicate."
        );
      }
    } finally {
      setLoading(false);
    }
  };

  const handleSubmit = async (data, extra = {}) => {
    const existingDraft = readDraft();
    if (
      existingDraft &&
      identityOf(existingDraft.snapshot || {}) !== identityOf(data)
    ) {
      // Never silently discard a pending submission. Its key and payload are
      // preserved until the user explicitly confirms a new submission.
      setPendingReplacement({ data, extra, previous: existingDraft });
      return;
    }
    await submitPossiblyWithNearbyCheck(data, existingDraft, extra);
  };

  const confirmReplacement = async () => {
    const replacement = pendingReplacement;
    setPendingReplacement(null);
    if (!replacement) return;
    clearDraft();
    setDraft(null);
    await submitPossiblyWithNearbyCheck(replacement.data, null, replacement.extra);
  };

  const retryOriginal = async () => {
    const current = readDraft();
    if (!current?.original_payload) return;
    await performSubmit(current.original_payload, current, {
      preserveSnapshot: true,
    });
  };

  // ── Nearby matching suggestions (G3) ─────────────────────────────────────
  // Advisory duplicate prevention: a read-only lookup before a NEW
  // submission. G2 flows that reuse an existing key (Retry Original, edited
  // saves of a pending submission) skip it entirely, and a failed check is
  // never presented as "no matches".
  const submitPossiblyWithNearbyCheck = async (data, draftMeta, extra = {}) => {
    // Offline: the nearby check cannot run and nothing can be sent - the
    // queue takes over directly (G7).
    if (!navigator.onLine) {
      await performSubmit(data, draftMeta, { photoFile: extra.photoFile });
      return;
    }
    if (draftMeta?.key) {
      await performSubmit(data, draftMeta, { photoFile: extra.photoFile });
      return;
    }
    if (
      data.lat === undefined ||
      data.lat === null ||
      data.lng === undefined ||
      data.lng === null
    ) {
      await performSubmit(data, draftMeta, { photoFile: extra.photoFile });
      return;
    }
    setLoading(true);
    try {
      const candidates = await treesApi.nearby({
        lat: data.lat,
        lng: data.lng,
        common_name: data.common_name || undefined,
        scientific_name: data.scientific_name || undefined,
      });
      if (candidates.length > 0) {
        setNearbyCandidates(candidates);
        setNearbyPendingData({ data, extra });
        return;
      }
      await performSubmit(data, draftMeta, { photoFile: extra.photoFile });
    } catch {
      setNearbyError(true);
      setNearbyPendingData({ data, extra });
    } finally {
      setLoading(false);
    }
  };

  const proceedPastNearbyCheck = async () => {
    const pending = nearbyPendingData;
    setNearbyCandidates(null);
    setNearbyError(false);
    setNearbyPendingData(null);
    if (pending)
      await performSubmit(pending.data, null, {
        photoFile: pending.extra?.photoFile,
      });
  };

  const cancelNearbyCheck = () => {
    setNearbyCandidates(null);
    setNearbyError(false);
    setNearbyPendingData(null);
    toast.info("Registration stopped. Nothing was submitted.");
  };

  return (
    <div className="p-8 max-w-2xl mx-auto">
      <Link
        to="/trees"
        className="inline-flex items-center gap-2 text-muted-foreground hover:text-foreground text-sm mb-6 transition-colors"
      >
        <ArrowLeft className="w-4 h-4" />
        Back to Inventory
      </Link>

      <div className="mb-6">
        <h1 className="font-fraunces text-3xl font-semibold">Add New Tree</h1>
        <p className="text-muted-foreground mt-1">
          Record a new tree entry with GPS location and measurements
        </p>
      </div>

      {draft && !conflict && !replayInfo && !pendingReplacement && (
        <div className="mb-6 rounded-xl border border-amber-300 bg-amber-50 p-4 text-sm">
          <p className="font-medium text-amber-900">
            {draft.status === "uncertain" || draft.status === "in_flight"
              ? "A previous save may have reached the server."
              : "Unfinished submission recovered from durable storage."}
          </p>
          <p className="mt-1 text-amber-800">
            {draft.snapshot?.common_name || "Unnamed tree"} · saved{" "}
            {draft.created_at ? new Date(draft.created_at).toLocaleString() : "earlier"}
            {draft.status === "uncertain" || draft.status === "in_flight"
              ? " - retrying uses the same submission key, so no duplicate can be created. The draft is saved in this browser and survives closing the tab."
              : " - restored from this browser's durable draft storage."}
          </p>
          <div className="mt-3 flex gap-2">
            {(draft.status === "uncertain" || draft.status === "in_flight") &&
              draft.original_payload && (
                <Button size="sm" variant="outline" onClick={retryOriginal}>
                  Retry Original Submission
                </Button>
              )}
            <Button size="sm" variant="outline" onClick={resumeDraft}>
              Resume &amp; Edit
            </Button>
            <Button size="sm" variant="ghost" onClick={discardDraft}>
              Discard
            </Button>
          </div>
          {(draft.status === "uncertain" || draft.status === "in_flight") &&
            draft.original_payload && (
              <p className="mt-2 text-xs text-amber-800">
                Retry Original re-sends exactly what was first submitted, under
                the same key. Resume &amp; Edit lets you correct the form;
                saving sends an edited submission under the same key and never
                replaces the original payload. Discard and Start New always
                ask for confirmation first.
              </p>
            )}
        </div>
      )}

      {nearbyCandidates && (
        <div className="mb-6 rounded-xl border border-amber-300 bg-amber-50 p-4 text-sm">
          <p className="font-medium text-amber-900">
            Possible existing trees nearby
          </p>
          <p className="mt-1 text-amber-800">
            {nearbyCandidates.length === 1
              ? "An existing record is close to this location."
              : `${nearbyCandidates.length} existing records are close to this location.`}{" "}
            Review them before registering a new tree. Nothing will be merged,
            overwritten, or rejected automatically.
          </p>
          <ul className="mt-3 space-y-2">
            {nearbyCandidates.map((candidate) => (
              <li
                key={candidate.tree_id}
                className="flex items-center justify-between gap-3 rounded-lg border border-amber-200 bg-white/60 p-2.5"
              >
                <div className="min-w-0">
                  <p className="truncate font-medium text-foreground">
                    {candidate.common_name}
                    {candidate.scientific_name
                      ? ` (${candidate.scientific_name})`
                      : ""}
                  </p>
                  <p className="text-xs text-muted-foreground">
                    ~{Math.round(candidate.distance_m)} m away
                    {candidate.barangay ? ` · ${candidate.barangay}` : ""} ·{" "}
                    {candidate.species_match === "exact"
                      ? "same species"
                      : candidate.species_match === "unknown"
                        ? "species not provided"
                        : "different species"}
                  </p>
                </div>
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => navigate(`/trees/${candidate.tree_id}`)}
                >
                  View record
                </Button>
              </li>
            ))}
          </ul>
          <div className="mt-3 flex gap-2">
            <Button size="sm" variant="outline" onClick={proceedPastNearbyCheck}>
              Register as a new tree anyway
            </Button>
            <Button size="sm" variant="ghost" onClick={cancelNearbyCheck}>
              Cancel
            </Button>
          </div>
        </div>
      )}

      {nearbyError && (
        <div className="mb-6 rounded-xl border border-amber-300 bg-amber-50 p-4 text-sm">
          <p className="font-medium text-amber-900">
            The nearby check could not be completed
          </p>
          <p className="mt-1 text-amber-800">
            Possible existing trees could not be verified (network or server
            problem). This is NOT the same as &quot;no matches&quot; - your
            registration is simply unchecked.
          </p>
          <div className="mt-3 flex gap-2">
            <Button size="sm" variant="outline" onClick={proceedPastNearbyCheck}>
              Continue without nearby check
            </Button>
            <Button size="sm" variant="ghost" onClick={cancelNearbyCheck}>
              Cancel
            </Button>
          </div>
        </div>
      )}

      {pendingReplacement && (
        <div className="mb-6 rounded-xl border border-amber-300 bg-amber-50 p-4 text-sm">
          <p className="font-medium text-amber-900">
            This form looks like a different tree.
          </p>
          <p className="mt-1 text-amber-800">
            The pending submission for{" "}
            <strong>
              {pendingReplacement.previous.snapshot?.common_name ||
                "Unnamed tree"}
            </strong>{" "}
            {pendingReplacement.previous.original_payload
              ? "may already have reached the server"
              : "is still saved in this tab"}
            . Its submission key and original payload stay untouched - and
            retryable - until you confirm.
          </p>
          <div className="mt-3 flex gap-2">
            <Button size="sm" variant="outline" onClick={confirmReplacement}>
              Start New Submission
            </Button>
            <Button
              size="sm"
              variant="ghost"
              onClick={() => setPendingReplacement(null)}
            >
              Keep pending submission
            </Button>
          </div>
        </div>
      )}

      {conflict && (
        <div className="mb-6 rounded-xl border border-red-300 bg-red-50 p-4 text-sm">
          <p className="font-medium text-red-900">
            This submission key already belongs to a different tree.
          </p>
          <p className="mt-1 text-red-800">
            Nothing was merged or overwritten.
            {conflict.treeId ? ` The existing record is tree #${conflict.treeId}.` : ""}
          </p>
          <div className="mt-3 flex gap-2">
            {conflict.treeId && (
              <Button size="sm" onClick={() => navigate(`/trees/${conflict.treeId}`)}>
                Open existing record
              </Button>
            )}
            <Button
              size="sm"
              variant="outline"
              onClick={() => {
                clearDraft();
                setDraft(null);
                setConflict(null);
                toast.info("Start a fresh save - a new submission key will be used.");
              }}
            >
              Start new submission
            </Button>
          </div>
        </div>
      )}

      {replayInfo && (
        <div className="mb-6 rounded-xl border border-blue-300 bg-blue-50 p-4 text-sm">
          <p className="font-medium text-blue-900">
            Already recorded as tree #{replayInfo.treeId} - no duplicate was created.
          </p>
          <p className="mt-1 text-blue-800">
            Your retry included data that differs from the saved record. Nothing was
            overwritten; review the record and update it manually if needed.
          </p>
          <ul className="mt-2 list-disc pl-5 text-blue-900">
            {Object.entries(replayInfo.differences).map(([field, values]) => (
              <li key={field}>
                <span className="font-medium">{field}</span>: saved{" "}
                {String(values.existing ?? "—")} vs submitted{" "}
                {String(values.submitted ?? "—")}
              </li>
            ))}
          </ul>
          <div className="mt-3">
            <Button
              size="sm"
              onClick={() => navigate(`/trees/${replayInfo.treeId}`)}
            >
              Open record to review and update
            </Button>
          </div>
        </div>
      )}

      <div className="bg-card border border-border rounded-xl p-6 shadow-sm">
        <TreeForm
          key={formKey}
          initial={formInitial}
          onSubmit={handleSubmit}
          loading={loading}
        />
      </div>
    </div>
  );
}
