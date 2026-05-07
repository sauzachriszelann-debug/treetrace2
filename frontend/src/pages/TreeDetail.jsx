import { useState } from "react";
import { useParams, Link, useNavigate } from "react-router-dom";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { treesApi } from "@/api/trees";
import { healthLogsApi } from "@/api/healthLogs";
import { useAuth } from "@/lib/AuthContext";
import HealthBadge from "@/components/trees/HealthBadge";
import QRCodeDisplay from "@/components/qr/QRCodeDisplay";
import TreeForm from "@/components/trees/TreeForm";
import HealthLogForm from "@/components/trees/HealthLogForm";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  ArrowLeft, MapPin, Ruler, Leaf, Calendar,
  Edit, Trash2, Activity, Plus,
} from "lucide-react";
import { format } from "date-fns";
import { toast } from "sonner";

export default function TreeDetail() {
  const { id }      = useParams();
  const navigate    = useNavigate();
  const { user }    = useAuth();
  const qc          = useQueryClient();
  const [editing, setEditing]         = useState(false);
  const [showLogForm, setShowLogForm] = useState(false);
  const [saving, setSaving]           = useState(false);
  const canManageOfficialTree = user?.role !== "citizen";

  const { data: tree, isLoading } = useQuery({
    queryKey: ["tree", id],
    queryFn: () => treesApi.get(id),
  });

  const { data: logs = [] } = useQuery({
    queryKey: ["healthlogs", id],
    queryFn: () => healthLogsApi.listByTree(id),
  });

  const handleUpdate = async (data) => {
    if (!canManageOfficialTree) {
      toast.error("Citizen accounts cannot edit official inventory trees.");
      setEditing(false);
      return;
    }
    setSaving(true);
    try {
      await treesApi.update(id, data);
      qc.invalidateQueries({ queryKey: ["tree", id] });
      qc.invalidateQueries({ queryKey: ["trees"] });
      toast.success("Tree updated!");
      setEditing(false);
    } catch {
      toast.error("Failed to update tree.");
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async () => {
    if (!confirm("Delete this tree record? This cannot be undone.")) return;
    try {
      await treesApi.delete(id);
      toast.success("Tree deleted");
      navigate("/trees");
    } catch {
      toast.error("Failed to delete. Admin access required.");
    }
  };

  const handleAddLog = async (data) => {
    if (!canManageOfficialTree) {
      toast.error("Citizen accounts cannot add official health assessments.");
      return;
    }
    try {
      await healthLogsApi.create({
        ...data,
        tree_id: Number(id),
      });
      qc.invalidateQueries({ queryKey: ["healthlogs", id] });
      qc.invalidateQueries({ queryKey: ["tree", id] });
      toast.success("Health assessment logged!");
      setShowLogForm(false);
    } catch {
      toast.error("Failed to save health log.");
    }
  };

  if (isLoading) {
    return (
      <div className="p-8">
        <div className="h-8 w-48 bg-muted rounded animate-pulse mb-4" />
        <div className="h-64 bg-muted rounded-xl animate-pulse" />
      </div>
    );
  }

  if (!tree) {
    return <div className="p-8 text-center text-muted-foreground">Tree not found.</div>;
  }

  return (
    <div className="p-8 max-w-5xl mx-auto">
      <Link
        to="/trees"
        className="inline-flex items-center gap-2 text-muted-foreground hover:text-foreground text-sm mb-6 transition-colors"
      >
        <ArrowLeft className="w-4 h-4" />
        Back to Inventory
      </Link>

      {/* Header */}
      <div className="flex items-start justify-between mb-6">
        <div>
          <div className="flex items-center gap-3 mb-1">
            <h1 className="font-fraunces text-3xl font-semibold">{tree.common_name}</h1>
            <HealthBadge status={tree.health_status} />
          </div>
          {tree.scientific_name && (
            <p className="text-muted-foreground italic">{tree.scientific_name}</p>
          )}
          <p className="text-muted-foreground text-sm mt-1">ID: {tree.id}</p>
        </div>

        {/* Endangered Warning */}
                  {tree.protected && (
                    <div className={`mt-4 p-4 rounded-xl border-2 flex items-start gap-3 ${
                      tree.status_code === "CR" ? "border-red-400 bg-red-50" :
                      tree.status_code === "EN" ? "border-orange-400 bg-orange-50" :
                      "border-yellow-400 bg-yellow-50"
                    }`}>
                      <span className="text-2xl">
                        {tree.status_code === "CR" ? "⛔" :
                         tree.status_code === "EN" ? "🚫" : "⚠️"}
                      </span>
                      <div>
                        <p className="font-bold text-sm">
                          {tree.status_code === "CR" ? "DO NOT CUT — Critically Endangered!" :
                           tree.status_code === "EN" ? "Protected — Cutting Prohibited" :
                           "Vulnerable Species"}
                        </p>
                        <p className="text-xs text-muted-foreground mt-1">
                          Listed as <strong>{tree.endangered_status}</strong> under DENR DAO 2017-11.
                          Cutting is {tree.cutting_allowed ? "allowed with permit" : "strictly prohibited"}.
                        </p>
                      </div>
                    </div>
                  )}

        <div className="flex gap-2">
          {canManageOfficialTree && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => setEditing(!editing)}
              className="flex items-center gap-2"
            >
              <Edit className="w-4 h-4" />
              {editing ? "Cancel" : "Edit"}
            </Button>
          )}
          {user?.role === "admin" && (
            <Button
              variant="destructive"
              size="sm"
              onClick={handleDelete}
              className="flex items-center gap-2"
            >
              <Trash2 className="w-4 h-4" />
              Delete
            </Button>
          )}
        </div>
      </div>

      {editing ? (
        <div className="bg-card border border-border rounded-xl p-6 shadow-sm mb-6">
          <h2 className="font-fraunces text-xl mb-4">Edit Tree Record</h2>
          <TreeForm initial={tree} onSubmit={handleUpdate} loading={saving} />
        </div>
      ) : (
        <Tabs defaultValue="details">
          <TabsList className="mb-4">
            <TabsTrigger value="details">Details</TabsTrigger>
            <TabsTrigger value="health">Health Logs ({logs.length})</TabsTrigger>
            <TabsTrigger value="qr">QR Code</TabsTrigger>
          </TabsList>

          {/* Details Tab */}
          <TabsContent value="details">
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
              {/* Photo */}
              <div className="lg:col-span-1">
                <div className="rounded-xl overflow-hidden border border-border bg-muted h-64 lg:h-80">
                  {tree.photo_url ? (
                    <img
                      src={tree.photo_url}
                      alt={tree.common_name}
                      className="w-full h-full object-cover"
                    />
                  ) : (
                    <div className="w-full h-full flex items-center justify-center text-muted-foreground">
                      <div className="text-center">
                        <div className="text-4xl mb-2">🌳</div>
                        <p className="text-sm">No photo</p>
                      </div>
                    </div>
                  )}
                </div>
              </div>

              {/* Info */}
              <div className="lg:col-span-2 space-y-4">
                <Card>
                  <CardHeader>
                    <CardTitle className="font-fraunces text-base">Measurements</CardTitle>
                  </CardHeader>
                  <CardContent className="grid grid-cols-2 gap-4 text-sm">
                    <Info label="DBH"          value={tree.dbh_cm    ? `${tree.dbh_cm} cm`    : "—"} icon={Ruler} />
                    <Info label="Height"       value={tree.height_m  ? `${tree.height_m} m`   : "—"} icon={Ruler} />
                    <Info label="Biomass"      value={tree.biomass_kg ? `${tree.biomass_kg} kg` : "—"} icon={Leaf} />
                    <Info label="Carbon Stock" value={tree.carbon_kg  ? `${tree.carbon_kg} kg`  : "—"} icon={Leaf} />
                  </CardContent>
                </Card>

                <Card>
                  <CardHeader>
                    <CardTitle className="font-fraunces text-base">Location</CardTitle>
                  </CardHeader>
                  <CardContent className="text-sm space-y-2">
                    <Info label="Barangay" value={tree.barangay || "—"} icon={MapPin} />
                    <Info label="City"     value={tree.city     || "—"} icon={MapPin} />
                    {tree.lat && tree.lng && (
                      <Info
                        label="GPS Coordinates"
                        value={`${tree.lat?.toFixed(6)}, ${tree.lng?.toFixed(6)}`}
                        icon={MapPin}
                      />
                    )}
                  </CardContent>
                </Card>

                <Card>
                  <CardContent className="pt-4 text-sm space-y-2">
                    <Info label="Recorded By"   value={tree.recorded_by_id   ? `User #${tree.recorded_by_id}` : "—"} icon={Activity} />
                    <Info
                      label="Date Recorded"
                      value={tree.date_recorded
                        ? format(new Date(tree.date_recorded), "MMM d, yyyy")
                        : "—"}
                      icon={Calendar}
                    />
                    {tree.notes && (
                      <div className="pt-2 text-muted-foreground">{tree.notes}</div>
                    )}
                  </CardContent>
                </Card>
              </div>
            </div>
          </TabsContent>

          {/* Health Logs Tab */}
          <TabsContent value="health">
            <div className="space-y-4">
              <div className="flex justify-between items-center">
                <h2 className="font-fraunces text-xl">Health Assessment History</h2>
                {canManageOfficialTree && (
                  <Button
                    size="sm"
                    onClick={() => setShowLogForm(!showLogForm)}
                    className="flex items-center gap-2"
                  >
                    <Plus className="w-4 h-4" />
                    Add Assessment
                  </Button>
                )}
              </div>

              {showLogForm && (
                <div className="bg-card border border-border rounded-xl p-4">
                  <HealthLogForm
                    onSubmit={handleAddLog}
                    onCancel={() => setShowLogForm(false)}
                  />
                </div>
              )}

              <div className="space-y-3">
                {logs.map((log) => (
                  <div key={log.id} className="bg-card border border-border rounded-xl p-4">
                    <div className="flex justify-between items-start mb-2">
                      <div>
                        <p className="font-medium text-sm">
                          {log.assessed_date
                            ? format(new Date(log.assessed_date), "MMMM d, yyyy")
                            : ""}
                        </p>
                        <p className="text-muted-foreground text-xs">by {log.assessed_by}</p>
                      </div>
                      <HealthBadge status={log.condition} />
                    </div>
                    {log.dbh_cm && (
                      <p className="text-xs text-muted-foreground">DBH: {log.dbh_cm} cm</p>
                    )}
                    {log.notes && (
                      <p className="text-sm text-foreground/80 mt-2">{log.notes}</p>
                    )}
                  </div>
                ))}
                {logs.length === 0 && (
                  <p className="text-center text-muted-foreground py-8">
                    No health assessments recorded yet.
                  </p>
                )}
              </div>
            </div>
          </TabsContent>

          {/* QR Tab */}
          <TabsContent value="qr">
            <div className="flex flex-col items-center py-8">
              <h2 className="font-fraunces text-xl mb-2">QR Code</h2>
              <p className="text-muted-foreground text-sm mb-6">
                Scan to instantly access this tree's profile
              </p>
              <QRCodeDisplay tree={tree} />
            </div>
          </TabsContent>
        </Tabs>
      )}
    </div>
  );
}

function Info({ label, value, icon: Icon }) {
  return (
    <div className="flex items-start gap-2">
      {Icon && <Icon className="w-4 h-4 text-muted-foreground mt-0.5 flex-shrink-0" />}
      <div>
        <span className="text-muted-foreground">{label}: </span>
        <span className="font-medium">{value}</span>
      </div>
    </div>
  );
}
