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
    <div className="p-8 max-w-4xl mx-auto">
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
        <div className="space-y-4">
          {submissions.map((submission) => {
            const meta = STATUS_META[submission.status] || STATUS_META.pending;
            return (
              <Card key={`${submission.isSpeciesSubmission ? "species" : "tree"}-${submission.id}`}>
                <CardContent className="p-4 space-y-3">
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <h2 className="font-semibold">
                          {submission.common_name || "Unnamed tree"}
                        </h2>
                        <Badge className={meta.className}>{meta.label}</Badge>
                      </div>
                      <div className="text-xs text-muted-foreground mt-1 space-y-1">
                        <p className="flex items-center gap-1">
                          <MapPin className="w-3 h-3" />
                          {submission.barangay || "Unknown barangay"}
                          {submission.lat != null && submission.lng != null
                            ? ` · ${submission.lat}, ${submission.lng}`
                            : ""}
                        </p>
                        <p>
                          Submitted{" "}
                          {submission.created_at
                            ? new Date(submission.created_at).toLocaleString()
                            : "earlier"}
                        </p>
                      </div>
                    </div>
                    {submission.photo_url ? (
                      <img
                        src={submission.photo_url}
                        alt="Submitted tree"
                        className="w-24 h-24 object-cover rounded-xl border shrink-0"
                      />
                    ) : null}
                  </div>

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
                      <div className="rounded-lg border bg-muted/30 p-3 text-sm flex items-center justify-between gap-3">
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
                      <Button size="sm" variant="outline" onClick={() => setDeleteTarget(submission)}>
                        Delete submission
                      </Button>
                    </div>
                  )}
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}
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
