import { useQuery, useQueryClient } from "@tanstack/react-query";
import { healthLogsApi } from "@/api/healthLogs";
import HealthBadge from "@/components/trees/HealthBadge";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Activity, Trash2 } from "lucide-react";
import { format } from "date-fns";
import { toast } from "sonner";
import { Link } from "react-router-dom";

export default function HealthLogs() {
  const qc = useQueryClient();

  const { data: logs = [], isLoading } = useQuery({
    queryKey: ["healthlogs"],
    queryFn: () => healthLogsApi.list({ limit: 200 }),
  });

  const handleDelete = async (id) => {
    if (!confirm("Delete this health log entry?")) return;
    try {
      await healthLogsApi.delete(id);
      qc.invalidateQueries({ queryKey: ["healthlogs"] });
      toast.success("Health log deleted.");
    } catch {
      toast.error("Failed to delete.");
    }
  };

  return (
    <div className="p-8">
      <div className="mb-6">
        <h1 className="font-fraunces text-3xl font-semibold">Health Logs</h1>
        <p className="text-muted-foreground mt-1">
          All tree health assessments — {logs.length} records
        </p>
      </div>

      {isLoading ? (
        <div className="space-y-3">
          {[1, 2, 3, 4].map((i) => (
            <div key={i} className="h-20 bg-muted rounded-xl animate-pulse" />
          ))}
        </div>
      ) : logs.length === 0 ? (
        <div className="text-center py-20 text-muted-foreground">
          <Activity className="w-16 h-16 mx-auto mb-4 opacity-20" />
          <p className="font-fraunces text-xl">No health logs yet</p>
          <p className="text-sm mt-1">Assessments will appear here once recorded from a tree's detail page.</p>
        </div>
      ) : (
        <div className="space-y-3">
          {logs.map((log) => (
            <Card key={log.id} className="border-border">
              <CardContent className="p-4">
                <div className="flex items-start justify-between">
                  <div className="flex items-start gap-4">
                    {/* Date */}
                    <div className="text-center min-w-[50px]">
                      <p className="text-xs text-muted-foreground">
                        {log.assessed_date
                          ? format(new Date(log.assessed_date), "MMM")
                          : "—"}
                      </p>
                      <p className="font-fraunces text-2xl font-semibold text-primary leading-none">
                        {log.assessed_date
                          ? format(new Date(log.assessed_date), "d")
                          : "—"}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        {log.assessed_date
                          ? format(new Date(log.assessed_date), "yyyy")
                          : ""}
                      </p>
                    </div>

                    <div className="border-l border-border pl-4">
                      <Link
                        to={`/trees/${log.tree_id}`}
                        className="font-medium text-foreground hover:text-primary transition-colors"
                      >
                        {log.tree_common_name || `Tree #${log.tree_id}`}
                      </Link>
                      <p className="text-sm text-muted-foreground">
                        Assessed by {log.assessed_by || "Unknown"}
                      </p>
                      {log.notes && (
                        <p className="text-sm mt-1 text-foreground/80">{log.notes}</p>
                      )}
                      {(log.dbh_cm || log.height_m) && (
                        <p className="text-xs text-muted-foreground mt-1">
                          {log.dbh_cm && `DBH: ${log.dbh_cm} cm`}
                          {log.dbh_cm && log.height_m && " · "}
                          {log.height_m && `Height: ${log.height_m} m`}
                        </p>
                      )}
                    </div>
                  </div>

                  <div className="flex items-center gap-3 ml-4 flex-shrink-0">
                    <HealthBadge status={log.condition} />
                    <Button
                      variant="ghost"
                      size="icon"
                      className="w-8 h-8 text-muted-foreground hover:text-destructive"
                      onClick={() => handleDelete(log.id)}
                    >
                      <Trash2 className="w-4 h-4" />
                    </Button>
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
