import MySubmissions from "@/pages/MySubmissions";
import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { treeSubmissionsApi } from "@/api/treeSubmissions";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { Textarea } from "@/components/ui/textarea";
import {
  CheckCircle2, Loader2, Mail, MapPin, Ruler, ShieldAlert,
  ClipboardList, TreePine, XCircle,
} from "lucide-react";
import { toast } from "sonner";
import { useAuth } from "@/lib/AuthContext";
import UnknownSpeciesReview from "@/pages/UnknownSpeciesReview";

const STAFF_ROLES = ["admin", "field_worker"];

function isStaff(roleValue) {
  const role = String(roleValue || "");
  return STAFF_ROLES.some((r) => role === r || role.endsWith(`.${r}`));
}

export default function TreeReviews() {
  const { user, isLoadingAuth } = useAuth();
  const [mySubmissionsOpen, setMySubmissionsOpen] = useState(false);

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
      <div className="mb-6 flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h1 className="font-fraunces text-3xl font-semibold">Tree Reviews</h1>
          <p className="text-muted-foreground mt-1">
            Identify submitted photos and approve tree records for the inventory.
          </p>
        </div>
        <Button type="button" variant="outline" className="shrink-0 self-start" onClick={() => setMySubmissionsOpen(true)}>
          <ClipboardList className="mr-2 h-4 w-4" />
          My Submissions
        </Button>
      </div>
      <ReviewQueue canIdentify={isAdmin(user.role)} reviewerId={user.id} />
      <Dialog open={mySubmissionsOpen} onOpenChange={setMySubmissionsOpen}>
        <DialogContent className="max-h-[90dvh] w-[calc(100%_-_2rem)] max-w-6xl overflow-y-auto rounded-xl">
          <div className="pr-6">
            <DialogTitle className="font-fraunces text-2xl">My Submissions</DialogTitle>
            <DialogDescription className="mt-2">Your submitted trees and their review status.</DialogDescription>
          </div>
          {mySubmissionsOpen && <MySubmissions embedded />}
        </DialogContent>
      </Dialog>
    </div>
  );
}

function isAdmin(role) {
  return role === "admin" || String(role).endsWith(".admin");
}

function ReviewQueue({ canIdentify, reviewerId }) {
  const qc = useQueryClient();
  const [statusFilter, setStatusFilter] = useState("pending");
  const [busyId, setBusyId] = useState(null);
  const [rejectingId, setRejectingId] = useState(null);
  const [rejectReason, setRejectReason] = useState("");
  const [confirmApproveId, setConfirmApproveId] = useState(null);
  const [reviewSpecies, setReviewSpecies] = useState({ common_name: "", scientific_name: "" });
  const [reviewLocation, setReviewLocation] = useState({ lat: "", lng: "" });

  const beginApproval = (submission) => {
    setReviewSpecies({
      common_name: submission.common_name || "",
      scientific_name: submission.scientific_name || "",
    });
    setReviewLocation({ lat: submission.lat == null ? "" : String(submission.lat), lng: submission.lng == null ? "" : String(submission.lng) });
    setConfirmApproveId(submission.id);
  };

  const {
    data: allSubmissions = [],
    isLoading,
    isError,
    error,
    refetch,
  } = useQuery({
    queryKey: ["submissions", "all"],
    queryFn: () => treeSubmissionsApi.list("all"),
  });

  const approvalSubmission = allSubmissions.find((entry) =>
    entry.id === confirmApproveId && entry.status === "pending" && (reviewerId == null || entry.submitted_by_id !== reviewerId),
  );
  const submissions = allSubmissions.filter((entry) =>
    statusFilter === "all" || entry.status === statusFilter,
  );
  const showSpeciesReview = canIdentify && ["pending", "all"].includes(statusFilter);
  const convertedIds = new Set(allSubmissions.map((entry) => entry.source_unknown_species_id));

  const afterAction = () => {
    qc.invalidateQueries({ queryKey: ["submissions"] });
    qc.invalidateQueries({ queryKey: ["trees"] });
  };

  const approve = async (submission) => {
    const commonName = reviewSpecies.common_name.trim();
    const scientificName = reviewSpecies.scientific_name.trim();
    if (!commonName) return;
    const lat = Number(reviewLocation.lat);
    const lng = Number(reviewLocation.lng);
    if (!reviewLocation.lat.trim() || !reviewLocation.lng.trim() || !Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
      toast.error("Provide valid latitude and longitude inside Panabo City before approval.");
      return;
    }
    const overrides = {};
    if (lat !== submission.lat) overrides.lat = lat;
    if (lng !== submission.lng) overrides.lng = lng;
    if (commonName !== (submission.common_name || "")) overrides.common_name = commonName;
    if (scientificName !== (submission.scientific_name || "")) {
      overrides.scientific_name = scientificName || null;
    }
    setBusyId(submission.id);
    try {
      const result = await treeSubmissionsApi.approve(submission.id, overrides);
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
      ) : !showSpeciesReview && submissions.length === 0 ? (
        <Card>
          <CardContent className="p-10 text-center text-muted-foreground">
            <TreePine className="w-10 h-10 mx-auto mb-3 opacity-40" />
            No {statusFilter === "all" ? "" : statusFilter} submissions.
          </CardContent>
        </Card>
      ) : (
        <div className="flex flex-col gap-4">
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
                      {s.source_unknown_species_id && (
                        <Badge variant="outline">Species submission #{s.source_unknown_species_id}</Badge>
                      )}
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

                <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-2 text-sm">
                  <Measure label="DBH" value={s.dbh_cm ? `${s.dbh_cm} cm` : "—"} />
                  <Measure label="Height" value={s.height_m ? `${s.height_m} m` : "—"} />
                  <Measure label="Carbon stock" value={s.carbon_kg != null ? `${s.carbon_kg} kg` : "Unavailable"} />
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
                {s.status === "pending" && (reviewerId != null && s.submitted_by_id === reviewerId ? (
                  <p className="rounded-lg border border-border bg-muted/30 p-3 text-sm">
                    You submitted this entry. Another admin or field worker can approve it.
                  </p>
                ) : (
                  <>
                    {rejectingId === s.id ? (
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
                          onClick={() => beginApproval(s)}
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
                ))}
              </CardContent>
            </Card>
          ))}
          {showSpeciesReview && (
            <UnknownSpeciesReview
              inQueue
              onReadyForApproval={beginApproval}
              pendingOnly={statusFilter === "pending"}
              convertedIds={convertedIds}
              showEmpty={submissions.length === 0}
            />
          )}
        </div>
      )}
      {approvalSubmission && (
        <Dialog open onOpenChange={(open) => {
          if (!open && busyId !== approvalSubmission.id) setConfirmApproveId(null);
        }}>
          <DialogContent className="sm:max-w-xl">
            <DialogTitle>Approve tree submission</DialogTitle>
            <DialogDescription>
              Approving adds this tree to the official inventory.
            </DialogDescription>
            <div className="grid gap-3 sm:grid-cols-2">
              <label className="space-y-1 text-sm">
                <span>Common name for inventory *</span>
                <Input
                  value={reviewSpecies.common_name}
                  onChange={(event) => setReviewSpecies({
                    ...reviewSpecies,
                    common_name: event.target.value,
                  })}
                  disabled={busyId === approvalSubmission.id}
                  required
                />
              </label>
              <label className="space-y-1 text-sm">
                <span>Scientific name for inventory</span>
                <Input
                  value={reviewSpecies.scientific_name}
                  onChange={(event) => setReviewSpecies({
                    ...reviewSpecies,
                    scientific_name: event.target.value,
                  })}
                  disabled={busyId === approvalSubmission.id}
                />
              </label>
            </div>
            <p className="text-sm text-muted-foreground">The server verifies the tree location against the Panabo City boundary before approval.</p>
            <div className="grid gap-3 sm:grid-cols-2">
              {[['lat', 'Latitude', -90, 90], ['lng', 'Longitude', -180, 180]].map(([field, label, min, max]) => (
                <label key={field} className="space-y-1 text-sm">
                  <span>{label} for inventory *</span>
                  <Input type="number" step="any" min={min} max={max} required
                    value={reviewLocation[field]} disabled={busyId === approvalSubmission.id}
                    onChange={(event) => setReviewLocation(previous => ({...previous, [field]: event.target.value}))} />
                </label>
              ))}
            </div>
            <div className="flex flex-wrap justify-end gap-2">
              <Button
                size="sm"
                onClick={() => approve(approvalSubmission)}
                disabled={busyId === approvalSubmission.id || !reviewSpecies.common_name.trim()}
              >
                {busyId === approvalSubmission.id && (
                  <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                )}
                Yes, approve
              </Button>
              <Button
                size="sm"
                variant="outline"
                onClick={() => setConfirmApproveId(null)}
                disabled={busyId === approvalSubmission.id}
              >
                Cancel
              </Button>
            </div>
          </DialogContent>
        </Dialog>
      )}
    </div>
  );
}

function StatusBadge({ status }) {
  if (status === "approved") return <Badge className="bg-emerald-600">Approved</Badge>;
  if (status === "rejected") return <Badge variant="destructive">Rejected</Badge>;
  if (status === "linked") return <Badge className="bg-blue-600">Linked</Badge>;
  return <Badge variant="outline">Ready for Approval</Badge>;
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
