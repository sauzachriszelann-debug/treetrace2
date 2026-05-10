import { useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { aiApi } from "@/api/ai";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { CheckCircle2, CircleHelp, Leaf, Loader2, Mail, MapPin, RotateCcw, XCircle } from "lucide-react";
import { toast } from "sonner";

export default function UnknownSpeciesReview() {
  const qc = useQueryClient();
  const [editing, setEditing] = useState({});
  const [savingId, setSavingId] = useState(null);
  const [statusFilter, setStatusFilter] = useState("all");

  const { data: submissions = [], isLoading } = useQuery({
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
    const draft = editing[entry.id] || {};
    const identifiedAs = draft.identified_as ?? entry.identified_as ?? entry.possible_name ?? "";
    const reviewNotes = draft.review_notes ?? entry.review_notes ?? "";

    if (action === "identified" && !identifiedAs.trim()) {
      toast.error("Enter the identified species name first.");
      return;
    }

    setSavingId(entry.id);
    try {
      await aiApi.reviewUnknown(entry.id, {
        reviewed: action !== "reopen",
        identified_as: action === "identified" ? identifiedAs : "",
        review_notes:
          action === "closed"
            ? reviewNotes || "Closed as unresolved. More field evidence is needed."
            : reviewNotes,
      });
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

  return (
    <div className="p-8 max-w-6xl mx-auto">
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

      {isLoading ? (
        <div className="h-40 bg-muted rounded-xl animate-pulse" />
      ) : filtered.length === 0 ? (
        <Card>
          <CardContent className="p-10 text-center text-muted-foreground">
            <Leaf className="w-10 h-10 mx-auto mb-3 opacity-40" />
            No submissions in this view.
          </CardContent>
        </Card>
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          {filtered.map((entry) => {
            const draft = editing[entry.id] || {};
            const candidates = Array.isArray(entry.ai_candidates) ? entry.ai_candidates : [];
            return (
              <Card key={entry.id}>
                <CardContent className="p-4 space-y-4">
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <div className="flex items-center gap-2 flex-wrap">
                        <h2 className="font-semibold">Submission #{entry.id}</h2>
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
                    ) : (
                      <CircleHelp className="w-5 h-5 text-amber-600" />
                    )}
                  </div>

                  {entry.photo_url ? (
                    <img
                      src={entry.photo_url}
                      alt="Unknown tree submission"
                      className="w-full h-60 object-cover rounded-xl border"
                    />
                  ) : (
                    <div className="h-60 rounded-xl bg-muted flex items-center justify-center text-muted-foreground">
                      No photo URL
                    </div>
                  )}

                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-sm">
                    <InfoBox label="User Guess" value={entry.possible_name || "Not provided"} />
                    <InfoBox label="Submitted Notes" value={entry.submitter_notes || "None"} />
                  </div>

                  {candidates.length > 0 && (
                    <div className="rounded-lg border bg-muted/30 p-3">
                      <p className="text-xs font-semibold text-muted-foreground mb-2">AI Candidates</p>
                      <div className="flex flex-wrap gap-2">
                        {candidates.slice(0, 5).map((candidate, index) => (
                          <Badge key={`${candidate?.common_name || candidate?.name || index}`} variant="outline">
                            {candidate?.common_name || candidate?.name || String(candidate)}
                          </Badge>
                        ))}
                      </div>
                    </div>
                  )}

                  <div className="space-y-2">
                    <Input
                      placeholder="Identified species name"
                      value={draft.identified_as ?? entry.identified_as ?? ""}
                      onChange={(e) => updateDraft(entry.id, "identified_as", e.target.value)}
                    />
                    <Textarea
                      placeholder="Review notes or reason if unresolved"
                      value={draft.review_notes ?? entry.review_notes ?? ""}
                      onChange={(e) => updateDraft(entry.id, "review_notes", e.target.value)}
                    />
                  </div>

                  <div className="flex flex-wrap gap-2">
                    <Button onClick={() => review(entry, "identified")} disabled={savingId === entry.id}>
                      {savingId === entry.id && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
                      Approve Identification
                    </Button>
                    <Button variant="outline" onClick={() => review(entry, "closed")} disabled={savingId === entry.id}>
                      Close Unresolved
                    </Button>
                    <Button variant="ghost" onClick={() => review(entry, "reopen")} disabled={savingId === entry.id}>
                      <RotateCcw className="w-4 h-4 mr-2" />
                      Reopen
                    </Button>
                  </div>
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
  return <Badge variant="outline">Pending</Badge>;
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
