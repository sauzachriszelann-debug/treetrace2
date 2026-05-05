import { useQuery } from "@tanstack/react-query";
import { treesApi } from "@/api/trees";
import { healthLogsApi } from "@/api/healthLogs";
import { useAuth } from "@/lib/AuthContext";
import StatsCard from "@/components/dashboard/StatsCard";
import HealthBadge from "@/components/trees/HealthBadge";
import { TreePine, Leaf, AlertTriangle, MapPin, Activity, Plus } from "lucide-react";
import { Link } from "react-router-dom";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Cell } from "recharts";
import { format } from "date-fns";

export default function Dashboard() {
  const { user } = useAuth();

  const { data: trees = [], isLoading } = useQuery({
    queryKey: ["trees"],
    queryFn: () => treesApi.list({ limit: 200 }),
  });

  const { data: logs = [] } = useQuery({
    queryKey: ["healthlogs"],
    queryFn: () => healthLogsApi.list({ limit: 50 }),
  });

  const stats = {
    total:       trees.length,
    healthy:     trees.filter((t) => t.health_status === "Healthy").length,
    fair:        trees.filter((t) => t.health_status === "Fair").length,
    poor:        trees.filter((t) => t.health_status === "Poor").length,
    totalCarbon: trees.reduce((s, t) => s + (t.carbon_kg || 0), 0),
    gpsTagged:   trees.filter((t) => t.lat && t.lng).length,
  };

  const chartData = [
    { name: "Healthy", count: stats.healthy, color: "#10b981" },
    { name: "Fair",    count: stats.fair,    color: "#f59e0b" },
    { name: "Poor",    count: stats.poor,    color: "#ef4444" },
  ];

  const recentTrees = trees.slice(0, 5);

  return (
    <div className="p-8">
      {/* Header */}
      <div className="flex items-start justify-between mb-8">
        <div>
          <h1 className="font-fraunces text-3xl font-semibold text-foreground">
            Welcome back, {user?.full_name?.split(" ")[0] || "User"}
          </h1>
          <p className="text-muted-foreground mt-1">
            TreeTrace Geo-Spatial Inventory — Panabo City
          </p>
        </div>
        <Link to="/add-tree">
          <Button className="flex items-center gap-2">
            <Plus className="w-4 h-4" />
            Add Tree
          </Button>
        </Link>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
        <StatsCard title="Total Trees"    value={stats.total}                                        icon={TreePine}     color="primary" />
        <StatsCard title="Healthy"        value={stats.healthy}                                      icon={Leaf}         color="emerald" />
        <StatsCard title="Need Attention" value={stats.fair + stats.poor}
          subtitle={`${stats.fair} Fair, ${stats.poor} Poor`}                                        icon={AlertTriangle} color="amber" />
        <StatsCard title="Carbon Stock"   value={`${(stats.totalCarbon / 1000).toFixed(2)} t`}
          subtitle="Total CO₂ equivalent"                                                            icon={Activity}     color="blue" />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Health Distribution Chart */}
        <Card className="lg:col-span-1">
          <CardHeader>
            <CardTitle className="font-fraunces text-lg">Health Distribution</CardTitle>
          </CardHeader>
          <CardContent>
            <ResponsiveContainer width="100%" height={180}>
              <BarChart data={chartData} barCategoryGap="30%">
                <XAxis dataKey="name" tick={{ fontSize: 12 }} />
                <YAxis tick={{ fontSize: 12 }} />
                <Tooltip />
                <Bar dataKey="count" radius={[6, 6, 0, 0]}>
                  {chartData.map((entry, index) => (
                    <Cell key={index} fill={entry.color} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
            <div className="mt-3 flex justify-between text-xs text-muted-foreground">
              <span className="flex items-center gap-1">
                <span className="w-2 h-2 rounded-full bg-emerald-500 inline-block" />
                {stats.gpsTagged} GPS tagged
              </span>
              <span>
                {((stats.gpsTagged / (stats.total || 1)) * 100).toFixed(0)}% mapped
              </span>
            </div>
          </CardContent>
        </Card>

        {/* Recent Trees */}
        <Card className="lg:col-span-2">
          <CardHeader className="flex flex-row items-center justify-between">
            <CardTitle className="font-fraunces text-lg">Recent Entries</CardTitle>
            <Link to="/trees" className="text-primary text-sm hover:underline">View all</Link>
          </CardHeader>
          <CardContent>
            {isLoading ? (
              <div className="space-y-3">
                {[1, 2, 3].map((i) => (
                  <div key={i} className="h-12 bg-muted rounded-lg animate-pulse" />
                ))}
              </div>
            ) : (
              <div className="space-y-2">
                {recentTrees.map((tree) => (
                  <Link
                    key={tree.id}
                    to={`/trees/${tree.id}`}
                    className="flex items-center justify-between p-3 rounded-lg hover:bg-muted transition-colors"
                  >
                    <div className="flex items-center gap-3">
                      <div className="w-9 h-9 rounded-lg bg-primary/10 flex items-center justify-center flex-shrink-0">
                        <TreePine className="w-4 h-4 text-primary" />
                      </div>
                      <div>
                        <p className="font-medium text-sm text-foreground">{tree.common_name}</p>
                        <div className="flex items-center gap-1.5 text-muted-foreground text-xs">
                          {tree.lat && (
                            <>
                              <MapPin className="w-3 h-3" />
                              {tree.barangay || "GPS tagged"}
                            </>
                          )}
                        </div>
                      </div>
                    </div>
                    <div className="flex items-center gap-3">
                      {tree.carbon_kg && (
                        <span className="text-xs text-muted-foreground">
                          {tree.carbon_kg.toFixed(1)} kg C
                        </span>
                      )}
                      <HealthBadge status={tree.health_status} />
                    </div>
                  </Link>
                ))}
                {recentTrees.length === 0 && (
                  <div className="text-center py-8 text-muted-foreground">
                    <TreePine className="w-10 h-10 mx-auto mb-2 opacity-30" />
                    <p className="text-sm">No trees recorded yet.</p>
                    <Link to="/add-tree" className="text-primary text-sm hover:underline mt-1 inline-block">
                      Add your first tree
                    </Link>
                  </div>
                )}
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Recent Health Logs */}
      {logs.length > 0 && (
        <Card className="mt-6">
          <CardHeader>
            <CardTitle className="font-fraunces text-lg">Recent Health Assessments</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-2">
              {logs.slice(0, 5).map((log) => (
                <div
                  key={log.id}
                  className="flex items-center justify-between p-3 rounded-lg bg-muted/50"
                >
                  <div>
                    <p className="text-sm font-medium">{log.tree_common_name || "Tree"}</p>
                    <p className="text-xs text-muted-foreground">
                      {log.assessed_date
                        ? format(new Date(log.assessed_date), "MMM d, yyyy")
                        : ""}{" "}
                      · {log.assessed_by}
                    </p>
                  </div>
                  <div className="flex items-center gap-2">
                    {log.notes && (
                      <p className="text-xs text-muted-foreground max-w-xs truncate">{log.notes}</p>
                    )}
                    <HealthBadge status={log.condition} />
                  </div>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
