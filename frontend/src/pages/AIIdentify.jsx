import { useState } from "react";
import { useNavigate, Link } from "react-router-dom";
import { useQueryClient } from "@tanstack/react-query";
import { treesApi } from "@/api/trees";
import { aiApi } from "@/api/ai";
import { treeSubmissionsApi } from "@/api/treeSubmissions";
import TreeForm from "@/components/trees/TreeForm";
import { useAuth } from "@/lib/AuthContext";
import { ArrowLeft } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";

const DRAFT_STORAGE_KEY = "treetrace_tree_draft";
// G4 citizen submissions keep their client_uuid across uncertain failures
// (safeguard D): the pending envelope lives in its own storage slot so the
// staff draft machinery above stays untouched.
const SUBMISSION_DRAFT_KEY = "treetrace_submission_draft";
const SUBMISSION_PREFILL_KEY = "treetrace_submission_prefill";

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

const readDraft = () => {
  try {
    const raw = sessionStorage.getItem(DRAFT_STORAGE_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
};
const writeDraft = (draft) => {
  try {
    sessionStorage.setItem(DRAFT_STORAGE_KEY, JSON.stringify(draft));
  } catch {
    /* storage unavailable: the draft simply is not recoverable */
  }
};
const clearDraft = () => {
  try {
    sessionStorage.removeItem(DRAFT_STORAGE_KEY);
  } catch {
    /* ignore */
  }
};

const readSubmissionDraft = () => {
  try {
    const raw = sessionStorage.getItem(SUBMISSION_DRAFT_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
};
const writeSubmissionDraft = (draft) => {
  try {
    sessionStorage.setItem(SUBMISSION_DRAFT_KEY, JSON.stringify(draft));
  } catch {
    /* storage unavailable: the pending envelope is not recoverable */
  }
};
const clearSubmissionDraft = () => {
  try {
    sessionStorage.removeItem(SUBMISSION_DRAFT_KEY);
  } catch {
    /* ignore */
  }
};

export default function AIIdentify() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { user } = useAuth();
  const [loading, setLoading] = useState(false);
  const [draft, setDraft] = useState(readDraft);
  const [formInitial, setFormInitial] = useState(() => {
    // One-shot prefill from My Submissions "Resubmit with Corrections".
    try {
      const raw = sessionStorage.getItem(SUBMISSION_PREFILL_KEY);
      if (raw) {
        sessionStorage.removeItem(SUBMISSION_PREFILL_KEY);
        return JSON.parse(raw);
      }
    } catch {
      /* ignore */
    }
    return {};
  });
  const [formKey, setFormKey] = useState(0);
  const [replayInfo, setReplayInfo] = useState(null);
  const [conflict, setConflict] = useState(null);
  const [pendingReplacement, setPendingReplacement] = useState(null);
  // G3 nearby matching: advisory duplicate prevention before NEW submissions.
  const [nearbyCandidates, setNearbyCandidates] = useState(null);
  const [nearbyError, setNearbyError] = useState(false);
  const [nearbyPendingData, setNearbyPendingData] = useState(null);
  const isCitizen = user?.role === "citizen";

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
    { preserveSnapshot = false } = {},
  ) => {
    setLoading(true);
    // Captured for the catch clause below (block-scoped to try is invisible
    // there): is there an earlier submission for this key that may exist on
    // the server?
    const hadPriorAttempt = Boolean(draftMeta?.original_payload);
    try {
      const key = draftMeta?.key || generateSubmissionKey();
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
        queryClient.invalidateQueries({ queryKey: ["trees"] });
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
      // A fresh 201 consumed this key server-side: drop the pending envelope.
      clearDraft();
      setDraft(null);
      queryClient.invalidateQueries({ queryKey: ["trees"] });
      toast.success("Tree submitted successfully.");
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

  // G4 citizen flow (Path A / Path B):
  //  * Species known  -> pending TREE SUBMISSION under an idempotency key
  //    that survives uncertain network failures (safeguard D).
  //  * Species unknown -> the existing unknown-species endpoint (Path B),
  //    which staff can later convert into a pending submission.
  const submitCitizenFlow = async (data) => {
    const hasSpecies = Boolean((data.common_name || "").trim());
    setLoading(true);
    try {
      if (!hasSpecies) {
        await aiApi.submitUnknown({
          photo_url: data.photo_url || "",
          barangay: data.barangay,
          location_description: [data.lat, data.lng].filter(Boolean).join(", "),
          possible_name: data.common_name,
          submitter_notes: data.notes || "Submitted from web AI scanner.",
          ai_candidates: [],
        });
        toast.success(
          "Submitted for expert review. Once identified, it can become a pending tree submission.",
        );
        navigate("/my-submissions");
        return;
      }

      // Safeguard D: reuse the pending key while a previous attempt is
      // unresolved; an explicit NEW submission always gets a fresh key.
      const prior = readSubmissionDraft();
      const sameIdentity =
        prior && identityOf(prior.payload || {}) === identityOf(data);
      const pending =
        prior &&
        (prior.status === "uncertain" || prior.status === "in_flight") &&
        sameIdentity
          ? prior
          : null;
      const key = pending?.key || generateSubmissionKey();
      writeSubmissionDraft({ key, status: "in_flight", payload: data });

      const response = await treeSubmissionsApi.create({
        ...data,
        client_uuid: key,
        source: "ai_identify",
        ai_candidates: [],
      });

      clearSubmissionDraft();
      queryClient.invalidateQueries({ queryKey: ["my-submissions"] });
      if (response?.status === "pending") {
        toast.success("Submitted for expert review.");
        navigate("/my-submissions");
      } else {
        // Idempotent replay of an earlier attempt for the same key.
        toast.success(
          "This submission was already recorded - no duplicate was created.",
        );
        navigate("/my-submissions");
      }
    } catch (error) {
      const status = error?.response?.status;
      const current = readSubmissionDraft();
      if (status === 409) {
        // The key belongs to a different submission. Nothing was merged.
        clearSubmissionDraft();
        toast.error(
          error.response.data?.detail?.message ||
            "This submission key belongs to a different tree. Nothing was merged - please submit again.",
        );
      } else if (status === 402 || status === 422) {
        // Definitive rejections: the request never created anything.
        clearSubmissionDraft();
        const detail = error.response.data?.detail;
        toast.error(
          typeof detail === "string"
            ? detail
            : "Please correct the highlighted fields and submit again.",
        );
      } else {
        // Network failure or server error: the request MAY have reached the
        // server. Keep the key and payload so a retry cannot duplicate it.
        if (current) {
          writeSubmissionDraft({ ...current, status: "uncertain" });
        }
        toast.error(
          "Connection problem - your submission is saved. Retrying will not create a duplicate.",
        );
      }
    } finally {
      setLoading(false);
    }
  };

  const handleSubmit = async (data) => {
    if (isCitizen) {
      await submitCitizenFlow(data);
      return;
    }
    const existingDraft = readDraft();
    if (
      existingDraft &&
      identityOf(existingDraft.snapshot || {}) !== identityOf(data)
    ) {
      // Never silently discard a pending submission. Its key and payload are
      // preserved until the user explicitly confirms a new submission.
      setPendingReplacement({ data, previous: existingDraft });
      return;
    }
    await submitPossiblyWithNearbyCheck(data, existingDraft);
  };

  const confirmReplacement = async () => {
    const replacement = pendingReplacement;
    setPendingReplacement(null);
    if (!replacement) return;
    clearDraft();
    setDraft(null);
    await submitPossiblyWithNearbyCheck(replacement.data, null);
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
  const submitPossiblyWithNearbyCheck = async (data, draftMeta) => {
    if (draftMeta?.key) {
      await performSubmit(data, draftMeta);
      return;
    }
    if (
      data.lat === undefined ||
      data.lat === null ||
      data.lng === undefined ||
      data.lng === null
    ) {
      await performSubmit(data, draftMeta);
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
        setNearbyPendingData(data);
        return;
      }
      await performSubmit(data, draftMeta);
    } catch {
      setNearbyError(true);
      setNearbyPendingData(data);
    } finally {
      setLoading(false);
    }
  };

  const proceedPastNearbyCheck = async () => {
    const data = nearbyPendingData;
    setNearbyCandidates(null);
    setNearbyError(false);
    setNearbyPendingData(null);
    if (data) await performSubmit(data, null);
  };

  const cancelNearbyCheck = () => {
    setNearbyCandidates(null);
    setNearbyError(false);
    setNearbyPendingData(null);
    toast.info("Registration stopped. Nothing was submitted.");
  };

  return (
    <div className="p-8 max-w-4xl mx-auto">
      <Link
        to="/trees"
        className="inline-flex items-center gap-2 text-muted-foreground hover:text-foreground text-sm mb-6 transition-colors"
      >
        <ArrowLeft className="w-4 h-4" />
        Back to Inventory
      </Link>

      <div className="mb-6">
        <h1 className="font-fraunces text-3xl font-semibold">AI Identify a Tree</h1>
        <p className="text-muted-foreground mt-2 max-w-2xl">
          Upload a photo and let the AI suggest the species, diameter, and height.
          {isCitizen
            ? "Citizen scans are submitted for expert review before they become official records."
            : "Once the tree is identified, submit it to the official inventory."}
        </p>
      </div>

      {!isCitizen && draft && !conflict && !replayInfo && !pendingReplacement && (
        <div className="mb-6 rounded-xl border border-amber-300 bg-amber-50 p-4 text-sm">
          <p className="font-medium text-amber-900">
            {draft.status === "uncertain" || draft.status === "in_flight"
              ? "A previous save may have reached the server."
              : "Unfinished submission recovered from this tab."}
          </p>
          <p className="mt-1 text-amber-800">
            {draft.snapshot?.common_name || "Unnamed tree"} · saved{" "}
            {draft.created_at ? new Date(draft.created_at).toLocaleString() : "earlier"}
            {draft.status === "uncertain" || draft.status === "in_flight"
              ? " - retrying uses the same submission key, so no duplicate can be created. Recovery lasts only while this browser tab stays open."
              : " - recovered from this tab only; closing the tab discards it."}
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

      {!isCitizen && nearbyCandidates && (
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

      {!isCitizen && nearbyError && (
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

      {!isCitizen && pendingReplacement && (
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

      {!isCitizen && conflict && (
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

      {!isCitizen && replayInfo && (
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
          submitLabel={isCitizen ? "Submit for Expert Review" : "Save Tree Record"}
          savingLabel={isCitizen ? "Submitting…" : "Saving…"}
          photoUploadPurpose={isCitizen ? "unknown_species" : "tree_photo"}
        />
      </div>
    </div>
  );
}
