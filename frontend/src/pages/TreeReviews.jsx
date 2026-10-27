import { useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { treeSubmissionsApi } from "@/api/treeSubmissions";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import {
  CheckCircle2, Leaf, Loader2, Mail, MapPin, Ruler, ShieldAlert,
  ClipboardList, TreePine, XCircle,
} from "lucide-react";
import { toast } from "sonner";
import { useAuth } from "@/lib/AuthContext";
import UnknownSpeciesReview from "@/pages/UnknownSpeciesReview";

// Phase 10C: ONE staff-only "Tree Reviews" surface with two tabs. The two
// workflows stay intentionally separate (approved G4 design):
//   * Tree Submissions -> /api/tree-submissions  (table tree_submissions)
//   * Unknown Species  -> /api/ai/unknown-species (table unknown_species)
// Only the PRESENTATION is combined; no data or business logic is merged.

const STAFF_ROLES = ["admin", "field_worker"];

function isStaff(roleValue) {
  const role = String(roleValue || "");
  return STAFF_ROLES.some((r) => role === r || role.endsWith(`.${r}`));
}

export default function TreeReviews() {
  const { user, isLoadingAuth } = useAuth();
  const [tab, setTab] = useState("submissions");

  // Task 10: protect against unauthorized citizen access. The backend also
  // enforces this (require_staff / require_admin); this is the UI guard.
  if (isLoadingAuth) {
    return (
      <div className="p-8">
        <div className="h-8 w-48 bg-muted rounded animate-pulse mb-4" />
        <div className="h-64 bg-muted rounded-xl animate-pulse" />
      </div>
    );
  }
  if (!isStaff(user?.role)) {
    return (
      <div className="p-8 max-w-2xl mx-auto">
        <Card>
          <CardContent className="p-10 text-center">
            <ShieldAlert className="w-10 h-10 mx-auto mb-3 text-amber-600" />
            <h2 className="font-fraunces text-xl font-semibold">
              Staff access required
            </h2>
            <p className="text-muted-foreground mt-2 text-sm">
              Tree Reviews is available to admins and field workers. Citizens
              can track their own submissions under My Submissions.
            </p>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="p-8 max-w-6xl mx-auto">
      <div className="mb-6">
        <h1 className="font-fraunces text-3xl font-semibold">Tree Reviews</h1>
        <p className="text-muted-foreground mt-1">
          Review citizen-submitted trees and unidentified species photos in one
          place. The two queues are tracked separately.
        </p>
      </div>

      <div className="flex items-center gap-1 bg-muted rounded-lg p-1 mb-6 w-fit">
        <button
          type="button"
          onClick={() => setTab("submissions")}
          className={`flex items-center gap-2 px-4 py-2 rounded-md text-sm font-medium transition-colors ${
            tab === "submissions"
              ? "bg-background text-foreground shadow-sm"
              : "text-muted-foreground hover:text-foreground"
          }`}
        >
          <ClipboardList className="w-4 h-4" />
          Tree Submissions
        </button>
        <button
          type="button"
          onClick={() => setTab("unknown")}
          className={`flex items-center gap-2 px-4 py-2 rounded-md text-sm font-medium transition-colors ${
            tab === "unknown"
              ? "bg-background text-foreground shadow-sm"
              : "text-muted-foreground hover:text-foreground"
          }`}
        >
          <Leaf className="w-4 h-4" />
          Unknown Species
        </button>
      </div>

      {/* Each tab keeps its OWN data source, endpoint and table. */}
      {tab === "submissions" ? <SubmissionsTab /> : <UnknownSpeciesReview />}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 1: citizen tree submissions (GET /api/tree-submissions)
// ─────────────────────────────────────────────────────────────────────────────

function SubmissionsTab() {
  const qc = useQueryClient();
  const [statusFilter, setStatusFilter] = useState("pending");
  const [busyId, setBusyId] = useState(null);
  const [rejectingId, setRejectingId] = useState(null);
  const [rejectReason, setRejectReason] = useState("");
  const [confirmApproveId, setConfirmApproveId] = useState(null);

  const {
    data: submissions = [],
    isLoading,
    isError,
    error,
    refetch,
  } = useQuery({
    queryKey: ["submissions", statusFilter],
    queryFn: () => treeSubmissionsApi.list(statusFilter),
  });

  const counts = useMemo(() => {
    // Only accurate when viewing "all"; otherwise show filtered length.
    return { shown: submissions.length };
  }, [submissions]);

  const afterAction = () => {
    qc.invalidateQueries({ queryKey: ["submissions"] });
    qc.invalidateQueries({ queryKey: ["trees"] });
  };

  const approve = async (submission) => {
    setBusyId(submission.id);
    try {
      const result = await treeSubmissionsApi.approve(submission.id, {});
      const treeId = result?.tree?.id;
      toast.success(
        treeId
          ? `Approved — created tree #${treeId}.`
          : "Submission approved.",
      );
      setConfirmApproveId(null);
      afterAction();
    } catch (err) {
      toast.error(err?.response?.data?.detail?.message || err?.response?.data?.detail || "Failed to approve.");
    } finally {
      setBusyId(null);
    }
  };

  const reject = async (submission) => {
    const reason = rejectReason.trim();
    if (!reason) {
      // Task 4: rejection reason is required (backend enforces 422 too).
      toast.error("A rejection reason is required.");
      return;
    }
    setBusyId(submission.id);
    try {
      await treeSubmissionsApi.reject(submission.id, reason);
      toast.success("Submission rejected.");
      setRejectingId(null);
      setRejectReason("");
      afterAction();
    } catch (err) {
      toast.error(err?.response?.data?.detail || "Failed to reject.");
    } finally {
      setBusyId(null);
    }
  };

  return (
    <div>
      <div className="flex flex-wrap items-center gap-2 mb-5">
        {[
          ["pending", "Pending"],
          ["approved", "Approved"],
          ["rejected", "Rejected"],
          ["linked", "Linked"],
          ["all", "All"],
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
        <span className="ml-auto text-sm text-muted-foreground">
          {counts.shown} shown
        </span>
      </div>

      {isLoading ? (
        <div className="space-y-3">
          {[0, 1].map((i) => (
            <div key={i} className="h-40 bg-muted rounded-xl animate-pulse" />
          ))}
        </div>
      ) : isError ? (
        <Card>
          <CardContent className="p-10 text-center">
            <XCircle className="w-10 h-10 mx-auto mb-3 text-red-500" />
            <p className="font-medium">Could not load submissions.</p>
            <p className="text-sm text-muted-foreground mt-1">
              {error?.response?.data?.detail || error?.message || "Unknown error"}
            </p>
            <Button className="mt-4" variant="outline" onClick={() => refetch()}>
              Try again
            </Button>
          </CardContent>
        </Card>
      ) : submissions.length === 0 ? (
        <Card>
          <CardContent className="p-10 text-center text-muted-foreground">
            <TreePine className="w-10 h-10 mx-auto mb-3 opacity-40" />
            No {statusFilter === "all" ? "" : statusFilter} submissions.
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-4">
          {submissions.map((s) => (
            <Card key={s.id}>
              <CardContent className="p-4 space-y-4">
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <h2 className="font-semibold">
                        {s.common_name || "Unnamed submission"}
                      </h2>
                      <StatusBadge status={s.status} />
                      {s.source && <Badge variant="outline">{s.source}</Badge>}
                    </div>
                    {s.scientific_name && (
                      <p className="text-xs italic text-muted-foreground mt-0.5">
                        {s.scientific_name}
                      </p>
                    )}
                    <div className="text-xs text-muted-foreground mt-2 space-y-1">
                      <p className="flex items-center gap-1">
                        <MapPin className="w-3 h-3" />
                        {s.barangay || "No barangay"}
                        {s.city ? ` | ${s.city}` : ""}
                      </p>
                      {s.submitted_by_name && (
                        <p className="flex items-center gap-1">
                          <Mail className="w-3 h-3" />
                          {s.submitted_by_name}
                          {s.submitted_by_email ? ` (${s.submitted_by_email})` : ""}
                        </p>
                      )}
                      <p className="flex items-center gap-1">
                        <ClipboardList className="w-3 h-3" />
                        Submitted #{s.id}
                        {s.created_at
                          ? ` | ${new Date(s.created_at).toLocaleString()}`
                          : ""}
                      </p>
                    </div>
                  </div>
                  {s.photo_url ? (
                    <img
                      src={s.photo_url}
                      alt={s.common_name || "Submitted tree"}
                      className="w-28 h-28 object-cover rounded-xl border flex-shrink-0"
                    />
                  ) : (
                    <div className="w-28 h-28 rounded-xl bg-muted flex items-center justify-center text-xs text-muted-foreground flex-shrink-0">
                      No photo
                    </div>
                  )}
                </div>

                <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 text-sm">
                  <Measure label="DBH" value={s.dbh_cm ? `${s.dbh_cm} cm` : "—"} />
                  <Measure label="Height" value={s.height_m ? `${s.height_m} m` : "—"} />
                  <Measure label="Health" value={s.health_status || "—"} />
                  <Measure
                    label="Recorded"
                    value={s.date_recorded ? String(s.date_recorded).slice(0, 10) : "—"}
                  />
                </div>

                {s.notes && (
                  <p className="text-sm text-muted-foreground rounded-lg border bg-muted/30 p-3">
                    {s.notes}
                  </p>
                )}

                {/* Decision bookkeeping (read-only). */}
                {s.status !== "pending" && (
                  <div className="text-xs text-muted-foreground rounded-lg border bg-muted/20 p-3 space-y-1">
                    {s.reviewed_by_name && (
                      <p>Reviewed by: {s.reviewed_by_name}</p>
                    )}
                    {s.review_reason && <p>Reason: {s.review_reason}</p>}
                    {s.approved_tree_id && (
                      <p>Linked tree: #{s.approved_tree_id}</p>
                    )}
                  </div>
                )}

                {/* Actions: only for pending rows. */}
                {s.status === "pending" && (
                  <>
                    {confirmApproveId === s.id ? (
                      <div className="rounded-lg border border-emerald-300 bg-emerald-50 p-3 space-y-2">
                        <p className="text-sm font-medium text-emerald-900">
                          Approve this submission? It becomes an official tree
                          record. This cannot be undone from here.
                        </p>
                        <div className="flex gap-2">
                          <Button
                            size="sm"
                            onClick={() => approve(s)}
                            disabled={busyId === s.id}
                          >
                            {busyId === s.id && (
                              <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                            )}
                            Yes, approve
                          </Button>
                          <Button
                            size="sm"
                            variant="outline"
                            onClick={() => setConfirmApproveId(null)}
                            disabled={busyId === s.id}
                          >
                            Cancel
                          </Button>
                        </div>
                      </div>
                    ) : rejectingId === s.id ? (
                      <div className="rounded-lg border border-red-300 bg-red-50 p-3 space-y-2">
                        <p className="text-sm font-medium text-red-900">
                          Rejection reason (required)
                        </p>
                        <Textarea
                          placeholder="Explain why this submission is rejected…"
                          value={rejectReason}
                          onChange={(e) => setRejectReason(e.target.value)}
                        />
                        <div className="flex gap-2">
                          <Button
                            size="sm"
                            variant="destructive"
                            onClick={() => reject(s)}
                            disabled={busyId === s.id || !rejectReason.trim()}
                          >
                            {busyId === s.id && (
                              <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                            )}
                            Confirm reject
                          </Button>
                          <Button
                            size="sm"
                            variant="outline"
                            onClick={() => {
                              setRejectingId(null);
                              setRejectReason("");
                            }}
                            disabled={busyId === s.id}
                          >
                            Cancel
                          </Button>
                        </div>
                      </div>
                    ) : (
                      <div className="flex flex-wrap gap-2">
                        <Button
                          size="sm"
                          onClick={() => setConfirmApproveId(s.id)}
                          disabled={busyId === s.id}
                        >
                          <CheckCircle2 className="w-4 h-4 mr-2" />
                          Approve
                        </Button>
                        <Button
                          size="sm"
                          variant="destructive"
                          onClick={() => setRejectingId(s.id)}
                          disabled={busyId === s.id}
                        >
                          <XCircle className="w-4 h-4 mr-2" />
                          Reject
                        </Button>
                      </div>
                    )}
                  </>
                )}
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}

function StatusBadge({ status }) {
  if (status === "approved") return <Badge className="bg-emerald-600">Approved</Badge>;
  if (status === "rejected") return <Badge variant="destructive">Rejected</Badge>;
  if (status === "linked") return <Badge className="bg-blue-600">Linked</Badge>;
  return <Badge variant="outline">Pending</Badge>;
}

function Measure({ label, value }) {
  return (
    <div className="rounded-lg border bg-muted/30 p-2">
      <p className="text-xs text-muted-foreground flex items-center gap-1">
        <Ruler className="w-3 h-3" />
        {label}
      </p>
      <p className="font-medium mt-0.5">{value}</p>
    </div>
  );
}
