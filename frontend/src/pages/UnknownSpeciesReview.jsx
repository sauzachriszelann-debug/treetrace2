import { useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { aiApi } from "@/api/ai";
import TreePhotoPreview from "@/components/trees/TreePhotoPreview";
import { treeSubmissionsApi } from "@/api/treeSubmissions";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { CheckCircle2, Leaf, Loader2, Mail, MapPin, RotateCcw, TreePine, XCircle } from "lucide-react";
import { toast } from "sonner";
import { useAuth } from "@/lib/AuthContext";

function speciesFields(entry, draft) {
  const candidate = Array.isArray(entry.ai_candidates) ? entry.ai_candidates[0] : null;
  const commonName = typeof candidate === "string"
    ? candidate
    : candidate?.common_name || candidate?.scientific_name || candidate?.name;
  return {
    commonName: draft.identified_as ?? (entry.identified_as || commonName || entry.possible_name || ""),
    scientificName: draft.identified_scientific_name ??
      (entry.identified_as ? entry.identified_scientific_name || "" : candidate?.scientific_name || ""),
  };
}

export default function UnknownSpeciesReview({ inQueue = false, pendingOnly = false, convertedIds, showEmpty = true, onReadyForApproval } = {}) {
  const qc = useQueryClient();
  const { user } = useAuth();
  const isOwnSubmission = (entry) => user?.id != null && entry.submitted_by_id === user.id;
  const [editing, setEditing] = useState({});
  const [savingId, setSavingId] = useState(null);
  const [convertingId, setConvertingId] = useState(null);
  const [statusFilter, setStatusFilter] = useState("all");

  const { data: submissions = [], isLoading, isError, refetch } = useQuery({
    queryKey: ["unknown-species"],
    queryFn: aiApi.listUnknown,
  });

  const counts = useMemo(() => ({
    total: submissions.length,
    pending: submissions.filter((entry) => !entry.reviewed).length,
    identified: submissions.filter((entry) => entry.review_status === "identified").length,
    closed: submissions.filter((entry) => entry.review_status === "closed").length,
  }), [submissions]);

  const filtered = submissions.filter((entry) => {
    if (inQueue) {
      return !convertedIds.has(entry.id) && (!pendingOnly || entry.review_status !== "closed");
    }
    if (statusFilter === "all") return true;
    if (statusFilter === "pending") return !entry.reviewed;
    return entry.review_status === statusFilter;
  });

  const updateDraft = (id, key, value) => {
    setEditing((current) => ({
      ...current,
      [id]: { ...(current[id] || {}), [key]: value },
    }));
  };

  const review = async (entry, action) => {
    if (isOwnSubmission(entry)) return;
    const draft = editing[entry.id] || {};
    const { commonName: identifiedAs, scientificName } = speciesFields(entry, draft);
    const reviewNotes = draft.review_notes ?? entry.review_notes ?? "";

    if (action === "identified" && !identifiedAs.trim()) {
      toast.error("Enter the identified species name first.");
      return;
    }

    setSavingId(entry.id);
    try {
      await aiApi.reviewUnknown(entry.id, {
        reviewed: action !== "reopen",
        identified_as: action === "identified" ? identifiedAs.trim() : "",
        identified_scientific_name: action === "identified" ? scientificName.trim() || null : null,
        review_notes:
          action === "closed"
            ? reviewNotes || "Closed as unresolved. More field evidence is needed."
            : reviewNotes,
      });
      if (inQueue && action === "identified") {
        await convert(entry);
        return;
      }
      qc.invalidateQueries({ queryKey: ["unknown-species"] });
      toast.success(
        action === "identified"
          ? "Species identification saved."
          : action === "closed"
            ? "Submission closed as unresolved."
            : "Submission reopened."
      );
    } catch (err) {
      toast.error(err?.response?.data?.detail || "Failed to update review.");
    } finally {
      setSavingId(null);
    }
  };

  // G4 Path B: turn an IDENTIFIED entry into a pending tree submission.
  // The unknown-species record itself is never modified; conversion is
  // replay-safe server-side (the unique source constraint returns the
  // already-created submission).
  const convert = async (entry) => {
    if (isOwnSubmission(entry)) return;
    setConvertingId(entry.id);
    try {
      const created = await treeSubmissionsApi.convertUnknownSpecies(entry.id);
      await qc.invalidateQueries({ queryKey: ["submissions"] });
      if (created?.status === "pending") onReadyForApproval?.(created);
      toast.success(
        created?.status === "pending"
          ? "Ready for inventory approval."
          : "A tree submission already exists for this entry.",
      );
    } catch (err) {
      toast.error(
        err?.response?.data?.detail ||
          (inQueue ? "Species saved. Use Save and Continue to retry." : "Species saved. Use Create Tree Submission to retry."),
      );
    } finally {
      await qc.invalidateQueries({ queryKey: ["unknown-species"] });
      setConvertingId(null);
    }
  };

  return (
    <div className={inQueue ? "contents" : "p-8 max-w-6xl mx-auto"}>
      {!inQueue && <>
      <div className="mb-6">
        <h1 className="font-fraunces text-3xl font-semibold">Unknown Species Review</h1>
        <p className="text-muted-foreground mt-1">
          Review community-submitted tree photos, identify species, and build the local TreeTrace knowledge base.
        </p>
      </div>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-5">
        <Metric label="Total" value={counts.total} />
        <Metric label="Pending" value={counts.pending} />
        <Metric label="Identified" value={counts.identified} />
        <Metric label="Closed" value={counts.closed} />
      </div>

      <div className="flex flex-wrap gap-2 mb-5">
        {[
          ["all", "All"],
          ["pending", "Pending"],
          ["identified", "Identified"],
          ["closed", "Closed"],
        ].map(([value, label]) => (
          <Button
            key={value}
            size="sm"
            variant={statusFilter === value ? "default" : "outline"}
            onClick={() => setStatusFilter(value)}
          >
            {label}
          </Button>
        ))}
      </div>

      </>}
      {isLoading ? (
        <div className="h-40 bg-muted rounded-xl animate-pulse" />
      ) : isError ? (
        <Card>
          <CardContent className="space-y-2 p-4">
            <p>Could not load species submissions.</p>
            <Button variant="outline" onClick={() => refetch()}>Retry species submissions</Button>
          </CardContent>
        </Card>
      ) : filtered.length === 0 ? showEmpty && (
        <Card>
          <CardContent className="p-10 text-center text-muted-foreground">
            <Leaf className="w-10 h-10 mx-auto mb-3 opacity-40" />
            No submissions in this view.
          </CardContent>
        </Card>
      ) : (
        <div className={inQueue ? "contents" : "grid grid-cols-1 lg:grid-cols-2 gap-4"}>
          {filtered.map((entry) => {
            const draft = editing[entry.id] || {};
            const ownSubmission = isOwnSubmission(entry);
            const candidates = Array.isArray(entry.ai_candidates) ? entry.ai_candidates : [];
            const { commonName, scientificName: reviewedScientificName } = speciesFields(entry, draft);
            return (
              <Card key={entry.id}>
                <CardContent className="p-4 space-y-4">
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <div className="flex items-center gap-2 flex-wrap">
                        <h2 className="font-semibold">Species submission #{entry.id}</h2>
                        <StatusBadge entry={entry} />
                      </div>
                      <div className="text-xs text-muted-foreground mt-1 space-y-1">
                        <p className="flex items-center gap-1">
                          <MapPin className="w-3 h-3" />
                          {entry.barangay || "Unknown barangay"} | {entry.location_description || "No location note"}
                        </p>
                        <p className="flex items-center gap-1">
                          <Mail className="w-3 h-3" />
                          {entry.submitted_by_name || "Unknown submitter"}
                          {entry.submitted_by_email ? ` (${entry.submitted_by_email})` : ""}
                        </p>
                      </div>
                    </div>
                    {entry.review_status === "identified" ? (
                      <CheckCircle2 className="w-5 h-5 text-emerald-600" />
                    ) : entry.review_status === "closed" ? (
                      <XCircle className="w-5 h-5 text-slate-500" />
                    ) : null}
                  </div>

                  <div className={inQueue ? "grid gap-4 lg:grid-cols-[minmax(0,2fr)_minmax(0,3fr)]" : "grid gap-4"}>
                    {entry.photo_url ? (
                      <TreePhotoPreview
                        src={entry.photo_url}
                        alt="Unknown tree submission"
                        className="w-full self-start overflow-hidden rounded-xl border bg-muted/30"
                        thumbnailClassName="h-60 w-full object-cover lg:h-72"
                      />
                    ) : (
                      <div className="h-60 lg:h-72 rounded-xl border bg-muted/30 flex items-center justify-center text-muted-foreground">
                        No photo submitted
                      </div>
                    )}
                    <div className="min-w-0 space-y-4">
                      {candidates.length > 0 && (
                        <div className="rounded-lg border bg-muted/30 p-3">
                          <div className="flex items-center justify-between gap-3 text-sm font-semibold">
                            <p>AI Candidates</p>
                            <p>Confidence</p>
                          </div>
                          <ul className="mt-2 divide-y divide-border border-t border-border">
                            {candidates.slice(0, 5).map((candidate, index) => {
                              const commonName = typeof candidate === "string"
                                ? candidate
                                : candidate?.common_name || candidate?.name;
                              const scientificName = candidate?.scientific_name;
                              const name = commonName || scientificName;
                              if (!name) return null;
                              const confidence = Number.isFinite(candidate?.confidence_percent)
                                ? `${candidate.confidence_percent}%`
                                : null;
                              return (
                                <li key={index} className="space-y-2 py-3 last:pb-0">
                                  <div className="flex items-start justify-between gap-3">
                                    <dl className="grid min-w-0 flex-1 gap-2 text-sm sm:grid-cols-2">
                                      <div>
                                        <dt className="text-xs text-muted-foreground">Suggested common name</dt>
                                        <dd className="break-words font-medium">{commonName || "Unavailable"}</dd>
                                      </div>
                                      <div>
                                        <dt className="text-xs text-muted-foreground">Suggested scientific name</dt>
                                        <dd className="break-words italic">{scientificName || "Unavailable"}</dd>
                                      </div>
                                    </dl>
                                    <span className="shrink-0 text-sm font-semibold tabular-nums">
                                      {confidence || "Unavailable"}
                                    </span>
                                  </div>
                                  <Button
                                    type="button"
                                    size="sm"
                                    variant="outline"
                                    className="h-auto max-w-full whitespace-normal text-left"
                                    onClick={() => {
                                      updateDraft(entry.id, "identified_as", name);
                                      updateDraft(entry.id, "identified_scientific_name", scientificName || "");
                                    }}
                                    disabled={ownSubmission || savingId === entry.id || convertingId === entry.id}
                                  >
                                    Use {name}
                                    {scientificName && scientificName !== name && ` (${scientificName})`}
                                    {confidence && ` \u00b7 ${confidence}`}
                                  </Button>
                                </li>
                              );
                            })}
                          </ul>
                        </div>
                      )}
                      {!ownSubmission && (
                        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-1 xl:grid-cols-2">
                          <label className="space-y-1 text-sm">
                            <span>Common name</span>
                            <Input
                              placeholder="Identified species name"
                              value={commonName}
                              onChange={(e) => updateDraft(entry.id, "identified_as", e.target.value)}
                              disabled={ownSubmission || savingId === entry.id || convertingId === entry.id}
                            />
                          </label>
                          <label className="space-y-1 text-sm">
                            <span>Scientific name</span>
                            <Input
                              value={reviewedScientificName}
                              onChange={(e) => updateDraft(entry.id, "identified_scientific_name", e.target.value)}
                              disabled={ownSubmission || savingId === entry.id || convertingId === entry.id}
                            />
                          </label>
                        </div>
                      )}
                    </div>
                  </div>

                  <div className="grid gap-2 sm:grid-cols-3">
                    <InfoBox label="DBH" value={entry.dbh_cm != null ? `${entry.dbh_cm} cm` : "Unavailable"} />
                    <InfoBox label="Height" value={entry.height_m != null ? `${entry.height_m} m` : "Unavailable"} />
                    <InfoBox label="Carbon stock" value={entry.carbon_kg != null ? `${entry.carbon_kg} kg` : "Unavailable"} />
                  </div>

                  {entry.submitter_notes?.trim() && (
                    <InfoBox label="Submitted Notes" value={entry.submitter_notes} />
                  )}

                  {ownSubmission ? (
                    <p className="rounded-lg border border-border bg-muted/30 p-3 text-sm">
                      You submitted this entry. Another admin can review it.
                    </p>
                  ) : (
                    <>
                      <Textarea
                        aria-label="Review notes"
                        className="min-h-[5rem]"
                        placeholder="Review notes or reason if unresolved"
                        value={draft.review_notes ?? entry.review_notes ?? ""}
                        onChange={(e) => updateDraft(entry.id, "review_notes", e.target.value)}
                      />
                      <div className="flex flex-wrap justify-end gap-2">
                        <Button onClick={() => review(entry, "identified")} disabled={savingId === entry.id}>
                          {savingId === entry.id && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
                          {inQueue ? (entry.review_status === "identified" ? "Save and Continue" : "Confirm Species") : "Approve Identification"}
                        </Button>
                        <Button variant="outline" onClick={() => review(entry, "closed")} disabled={savingId === entry.id}>
                          Close Unresolved
                        </Button>
                        <Button variant="ghost" onClick={() => review(entry, "reopen")} disabled={savingId === entry.id}>
                          <RotateCcw className="w-4 h-4 mr-2" />
                          Reopen
                        </Button>
                      </div>
                    </>
                  )}

                  {!ownSubmission && !inQueue && entry.review_status === "identified" && (
                    <div className="rounded-lg border bg-muted/30 p-3 text-sm space-y-2">
                      <p className="text-xs font-semibold text-muted-foreground">
                        Turn identification into an official tree submission
                      </p>
                      <p className="text-muted-foreground">
                        Creates a pending tree submission from this entry for
                        the review queue. The entry above is kept unchanged as
                        the identification record.
                      </p>
                      <Button
                        size="sm"
                        onClick={() => convert(entry)}
                        disabled={convertingId === entry.id}
                      >
                        {convertingId === entry.id ? (
                          <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                        ) : (
                          <TreePine className="w-4 h-4 mr-2" />
                        )}
                        Create Tree Submission
                      </Button>
                    </div>
                  )}
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
}

function StatusBadge({ entry }) {
  if (entry.review_status === "identified") {
    return <Badge className="bg-emerald-600">Identified</Badge>;
  }
  if (entry.review_status === "closed") {
    return <Badge variant="secondary">Closed</Badge>;
  }
  return <Badge variant="outline">Needs Species ID</Badge>;
}

function InfoBox({ label, value }) {
  return (
    <div className="rounded-lg border bg-muted/30 p-3">
      <p className="text-xs font-semibold text-muted-foreground">{label}</p>
      <p className="text-sm mt-1">{value}</p>
    </div>
  );
}

function Metric({ label, value }) {
  return (
    <div className="rounded-lg border bg-muted/30 p-3">
      <p className="text-muted-foreground text-xs">{label}</p>
      <p className="text-xl font-bold">{value}</p>
    </div>
  );
}
