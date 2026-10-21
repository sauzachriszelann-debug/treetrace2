import { useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { treeSubmissionsApi } from "@/api/treeSubmissions";
import { Card, CardContent } from "@/components/ui/card";
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
  pending: { label: "Pending Review", className: "bg-amber-600", icon: Clock3 },
  approved: { label: "Approved", className: "bg-emerald-600", icon: CheckCircle2 },
  rejected: { label: "Rejected", className: "bg-slate-500", icon: XCircle },
  linked: { label: "Linked to Existing Tree", className: "bg-blue-600", icon: Link2 },
};

export default function MySubmissions() {
  const navigate = useNavigate();
  const { data: submissions = [], isLoading } = useQuery({
    queryKey: ["my-submissions"],
    queryFn: treeSubmissionsApi.my,
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
          health_status: submission.health_status || "Healthy",
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

      {isLoading ? (
        <div className="h-40 bg-muted rounded-xl animate-pulse" />
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
            const StatusIcon = meta.icon;
            return (
              <Card key={submission.id}>
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
                    <p className="text-xs text-muted-foreground">
                      Awaiting review by an admin or field worker.
                      <Loader2 className="w-3 h-3 inline ml-1 animate-spin opacity-50" />
                    </p>
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
