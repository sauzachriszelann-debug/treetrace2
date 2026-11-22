import TreePhotoPreview from '@/components/trees/TreePhotoPreview';
import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { treeSubmissionsApi } from "@/api/treeSubmissions";
import { Card, CardContent } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Clock3,
  ExternalLink,
  Leaf,
  Loader2,
  MapPin,
  RotateCcw,
  XCircle,
  CheckCircle2,
  Link2,
} from "lucide-react";

const PREFILL_KEY = "treetrace_submission_prefill";

const STATUS_META = {
  closed: { label: "Closed as Unresolved", className: "bg-slate-500", icon: XCircle },
  pending: { label: "Pending Review", className: "bg-amber-600", icon: Clock3 },
  approved: { label: "Approved", className: "bg-emerald-600", icon: CheckCircle2 },
  rejected: { label: "Rejected", className: "bg-slate-500", icon: XCircle },
  linked: { label: "Linked to Existing Tree", className: "bg-blue-600", icon: Link2 },
};

export default function MySubmissions() {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const [deleteTarget, setDeleteTarget] = useState(null);
  const [selectedSubmission, setSelectedSubmission] = useState(null);
  const { data: treeSubmissions = [], isLoading: loadingTrees, isError: treesError } = useQuery({
    queryKey: ["my-submissions"],
    queryFn: treeSubmissionsApi.my,
  });

  const { data: speciesSubmissions = [], isLoading: loadingSpecies, isError: speciesError } = useQuery({
    queryKey: ["my-species-submissions"],
    queryFn: treeSubmissionsApi.mySpecies,
  });
  const converted = new Set(treeSubmissions.map((entry) => entry.source_unknown_species_id));
  const submissions = [
    ...treeSubmissions,
    ...speciesSubmissions.filter((entry) => !converted.has(entry.id)).map((entry) => ({
      ...entry,
      isSpeciesSubmission: true,
      common_name: entry.identified_as || entry.ai_candidates?.[0]?.common_name || "Unknown species",
      status: entry.review_status === "closed" ? "closed" : "pending",
    })),
  ].sort((a, b) => (b.created_at || "").localeCompare(a.created_at || ""));

  const remove = useMutation({
    mutationFn: (entry) => treeSubmissionsApi.deleteMine(entry.id, entry.isSpeciesSubmission),
    onSuccess: () => {
      setDeleteTarget(null);
      setSelectedSubmission(null);
      toast.success("Submission deleted.");
    },
    onError: (error) => {
      toast.error(error?.response?.data?.detail || "Could not delete the submission.");
    },
    onSettled: () => Promise.all(
      [["my-submissions"], ["my-species-submissions"], ["submissions"], ["unknown-species"]]
        .map((queryKey) => qc.invalidateQueries({ queryKey })),
    ),
  });

  const resubmit = (submission) => {
    // A rejected submission is immutable; resubmitting starts a FRESH
    // submission (new client_uuid is generated on the next save) pre-filled
    // with the original data so the citizen can address the review reason.
    try {
      sessionStorage.setItem(
        PREFILL_KEY,
        JSON.stringify({
          common_name: submission.common_name || "",
          scientific_name: submission.scientific_name || "",
          dbh_cm: submission.dbh_cm ?? "",
          height_m: submission.height_m ?? "",
          health_status: submission.health_status || "Not assessed",
          barangay: submission.barangay || "",
          lat: submission.lat ?? "",
          lng: submission.lng ?? "",
          notes: submission.notes || "",
          photo_url: submission.photo_url || "",
        }),
      );
    } catch {
      /* storage unavailable: resubmit simply starts blank */
    }
    navigate("/ai-identify");
  };

  return (
    <div className="mx-auto max-w-6xl p-4 sm:p-6 lg:p-8">
      <div className="mb-6">
        <h1 className="font-fraunces text-3xl font-semibold">My Submissions</h1>
        <p className="text-muted-foreground mt-1">
          Trees you submitted for expert review. Approved submissions become
          official inventory records.
        </p>
      </div>

      {loadingTrees || loadingSpecies ? (
        <div className="h-40 bg-muted rounded-xl animate-pulse" />
      ) : treesError || speciesError ? (
        <p role="alert" className="text-sm text-destructive">Could not load your submissions.</p>
      ) : submissions.length === 0 ? (
        <Card>
          <CardContent className="p-10 text-center text-muted-foreground">
            <Leaf className="w-10 h-10 mx-auto mb-3 opacity-40" />
            <p>You have not submitted any trees yet.</p>
            <Button className="mt-4" onClick={() => navigate("/ai-identify")}>
              Submit a Tree for Review
            </Button>
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {submissions.map((entry) => {
            const meta = STATUS_META[entry.status] || STATUS_META.pending;
            return (
              <button
                type="button"
                key={`${entry.isSpeciesSubmission ? "species" : "tree"}-${entry.id}`}
                onClick={() => setSelectedSubmission(entry)}
                aria-label={`View submission: ${entry.common_name || "Unnamed tree"}`}
                className="group overflow-hidden rounded-xl border bg-card text-left shadow-sm transition hover:border-primary/50 hover:shadow-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
              >
                <div className="flex items-start gap-3 p-4">
                  {entry.photo_url ? (
                    <img src={entry.photo_url} alt="" className="h-20 w-20 shrink-0 rounded-lg border object-cover" />
                  ) : (
                    <div className="flex h-20 w-20 shrink-0 items-center justify-center rounded-lg bg-muted">
                      <Leaf className="h-7 w-7 text-muted-foreground" />
                    </div>
                  )}
                  <div className="min-w-0 flex-1">
                    <h2 className="truncate font-semibold" title={entry.common_name || "Unnamed tree"}>{entry.common_name || "Unnamed tree"}</h2>
                    <Badge className={`${meta.className} mt-1 max-w-full whitespace-normal text-left`}>{meta.label}</Badge>
                    <p className="mt-2 truncate text-xs text-muted-foreground">{entry.barangay || "Unknown barangay"}</p>
                    <p className="mt-1 text-xs text-muted-foreground">{entry.created_at ? new Date(entry.created_at).toLocaleDateString() : "Date unavailable"}</p>
                  </div>
                </div>
                <div className="border-t px-4 py-2 text-right text-xs font-medium text-primary group-hover:underline">View details</div>
              </button>
            );
          })}
        </div>
      )}
      <Dialog open={Boolean(selectedSubmission)} onOpenChange={(open) => { if (!open) setSelectedSubmission(null); }}>
        <DialogContent className="max-h-[85dvh] w-[calc(100%_-_2rem)] max-w-4xl overflow-y-auto rounded-xl">
          <div className="pr-6">
            <DialogTitle className="font-fraunces text-xl">{selectedSubmission?.common_name || "Submission details"}</DialogTitle>
            <DialogDescription className="mt-2">Full details and review status of your submission.</DialogDescription>
          </div>
          {selectedSubmission && (() => {
            const submission = selectedSubmission;
            const meta = STATUS_META[submission.status] || STATUS_META.pending;
            return <div className={`grid items-start gap-5 ${submission.photo_url ? "md:grid-cols-[minmax(0,0.9fr)_minmax(0,1.1fr)]" : ""}`}>
              {submission.photo_url && <div className="min-w-0">
                <TreePhotoPreview src={submission.photo_url} label="Submitted tree photo" alt="Submitted tree"
                  className="w-full overflow-hidden rounded-xl border bg-muted/40 p-2"
                  thumbnailClassName="max-h-[55dvh] w-full rounded-lg object-contain" />
                <p className="mt-2 text-center text-xs text-muted-foreground">Click photo to enlarge</p>
              </div>}
              <div className="min-w-0 space-y-4">
                <Badge className={meta.className}>{meta.label}</Badge>
              <dl className="grid gap-4 rounded-xl border p-4 text-sm sm:grid-cols-2">
                <div><dt className="text-xs text-muted-foreground">Scientific name</dt><dd className="mt-1 italic">{submission.scientific_name || "Not identified"}</dd></div>
                <div><dt className="text-xs text-muted-foreground">Submitted</dt><dd className="mt-1">{submission.created_at ? new Date(submission.created_at).toLocaleString() : "Date unavailable"}</dd></div>
                <div className="sm:col-span-2"><dt className="flex items-center gap-1 text-xs text-muted-foreground"><MapPin className="h-3 w-3" />Location</dt><dd className="mt-1">{[submission.barangay, submission.city, submission.province].filter(Boolean).join(", ") || submission.location_description || "Location unavailable"}</dd></div>
                {submission.lat != null && submission.lng != null && <div className="sm:col-span-2"><dt className="text-xs text-muted-foreground">GPS coordinates</dt><dd className="mt-1 break-words">{Number(submission.lat).toFixed(6)}, {Number(submission.lng).toFixed(6)}</dd></div>}
                <div><dt className="text-xs text-muted-foreground">DBH</dt><dd className="mt-1">{submission.dbh_cm != null ? `${submission.dbh_cm} cm` : "Not provided"}</dd></div>
                <div><dt className="text-xs text-muted-foreground">Height</dt><dd className="mt-1">{submission.height_m != null ? `${submission.height_m} m` : "Not provided"}</dd></div>
                {submission.health_status && <div><dt className="text-xs text-muted-foreground">Health status</dt><dd className="mt-1">{submission.health_status}</dd></div>}
              </dl>
              {(submission.notes || submission.submitter_notes) && <div className="rounded-xl border p-4 text-sm"><p className="mb-1 text-xs font-semibold text-muted-foreground">Notes</p><p className="whitespace-pre-wrap break-words">{submission.notes || submission.submitter_notes}</p></div>}
              {submission.status === "closed" && <p className="rounded-lg border bg-muted/30 p-3 text-sm">{submission.review_reason || "This submission was closed as unresolved."}</p>}
                  {submission.status === "rejected" && (
                    <div className="rounded-lg border bg-muted/30 p-3 text-sm">
                      <p className="text-xs font-semibold text-muted-foreground">
                        Review decision
                      </p>
                      <p className="mt-1">
                        {submission.review_reason || "No reason recorded."}
                      </p>
                      {submission.reviewed_at && (
                        <p className="mt-1 text-xs text-muted-foreground">
                          {submission.reviewed_by_name
                            ? `Reviewed by ${submission.reviewed_by_name} · `
                            : ""}
                          {new Date(submission.reviewed_at).toLocaleString()}
                        </p>
                      )}
                    </div>
                  )}

                  {(submission.status === "approved" ||
                    submission.status === "linked") &&
                    submission.approved_tree_id && (
                      <div className="rounded-lg border bg-muted/30 p-3 text-sm flex flex-col items-start justify-between gap-3 sm:flex-row sm:items-center">
                        <p>
                          {submission.status === "approved"
                            ? "This submission is now an official inventory record."
                            : "This submission was matched to an existing inventory record."}
                          {submission.reviewed_at &&
                            submission.reviewed_by_name && (
                              <>
                                {" "}
                                Reviewed by {submission.reviewed_by_name} on{" "}
                                {new Date(
                                  submission.reviewed_at,
                                ).toLocaleString()}
                                .
                              </>
                            )}
                        </p>
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() =>
                            navigate(`/trees/${submission.approved_tree_id}`)
                          }
                        >
                          <ExternalLink className="w-4 h-4 mr-1" />
                          Open Tree
                        </Button>
                      </div>
                    )}

                  {submission.status === "rejected" && (
                    <Button size="sm" variant="outline" onClick={() => resubmit(submission)}>
                      <RotateCcw className="w-4 h-4 mr-1" />
                      Resubmit with Corrections
                    </Button>
                  )}

                  {submission.status === "pending" && (
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <p className="text-xs text-muted-foreground">
                        {submission.isSpeciesSubmission
                          ? "Awaiting species review."
                          : "Awaiting inventory approval."}
                      </p>
                      <Button size="sm" variant="outline" onClick={() => { setSelectedSubmission(null); setDeleteTarget(submission); }}>
                        Delete submission
                      </Button>
                    </div>
                  )}
              </div>
            </div>;
          })()}
        </DialogContent>
      </Dialog>
      <Dialog open={Boolean(deleteTarget)} onOpenChange={(open) => {
        if (!open && !remove.isPending) setDeleteTarget(null);
      }}>
        <DialogContent>
          <DialogTitle>Delete this submission?</DialogTitle>
          <DialogDescription>
            {deleteTarget?.common_name || "This entry"} will be removed from My Submissions and the review queue.
          </DialogDescription>
          <div className="flex flex-wrap justify-end gap-2">
            <Button variant="outline" onClick={() => setDeleteTarget(null)} disabled={remove.isPending}>
              Cancel
            </Button>
            <Button variant="destructive" onClick={() => remove.mutate(deleteTarget)} disabled={remove.isPending}>
              {remove.isPending && <Loader2 className="w-4 h-4 animate-spin" />}
              Delete submission
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}
