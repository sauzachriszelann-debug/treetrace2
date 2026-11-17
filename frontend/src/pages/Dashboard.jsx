import { useQuery } from "@tanstack/react-query";
import { treesApi } from "@/api/trees";
import { healthLogsApi } from "@/api/healthLogs";
import { plantingApi } from "@/api/planting";
import { useAuth } from "@/lib/AuthContext";
import StatsCard from "@/components/dashboard/StatsCard";
import HealthBadge from "@/components/trees/HealthBadge";
import { TreePine, Leaf, AlertTriangle, MapPin, Activity, Plus, Sprout } from "lucide-react";
import { Link, useNavigate } from "react-router-dom";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Cell } from "recharts";
import { format } from "date-fns";
import { formatCarbonKg } from "@/lib/format";

const carbonNumber = new Intl.NumberFormat("en-PH", { maximumFractionDigits: 2 });
const compactCarbonNumber = new Intl.NumberFormat("en-PH", { notation: "compact" });

export default function Dashboard() {
  const { user } = useAuth();
  const navigate = useNavigate();

  const { data: trees = [], isLoading, isError } = useQuery({
    queryKey: ["trees", "dashboard"],
    queryFn: async () => {
      const limit = 200;
      const records = [];
      for (let skip = 0; ; skip += limit) {
        const page = await treesApi.list({ skip, limit });
        records.push(...page);
        if (page.length < limit) return records;
      }
    },
  });

  const { data: logs = [] } = useQuery({
    queryKey: ["healthlogs"],
    queryFn: () => healthLogsApi.list({ limit: 50 }),
  });

  const { data: planting = { suggestions: [] } } = useQuery({
    queryKey: ["planting-suggestions-dashboard"],
    queryFn: () => plantingApi.suggestions(),
  });

  const { data: plantingRecords = [] } = useQuery({
    queryKey: ["planting-records-dashboard"],
    queryFn: () => plantingApi.list(),
  });

  const barangays = new Map();
  let totalCarbon = 0;
  for (const tree of trees) {
    const name = tree.barangay?.trim() || "Unassigned";
    const key = name.toLowerCase();
    const row = barangays.get(key) ?? { name, total: 0, estimated: 0, carbonKg: 0 };
    row.total += 1;
    if (Number.isFinite(tree.carbon_kg) && tree.carbon_kg >= 0) {
      row.estimated += 1;
      row.carbonKg += tree.carbon_kg;
      totalCarbon += tree.carbon_kg;
    }
    barangays.set(key, row);
  }
  const carbonByBarangay = [...barangays.values()]
    .filter((row) => row.estimated > 0)
    .sort((a, b) => b.carbonKg - a.carbonKg || a.name.localeCompare(b.name));

  const stats = {
    total: trees.length,
    healthy: trees.filter((t) => t.health_status === "Healthy").length,
    fair: trees.filter((t) => t.health_status === "Fair").length,
    poor: trees.filter((t) => t.health_status === "Poor").length,
    notAssessed: trees.filter((t) => !["Healthy", "Fair", "Poor"].includes(t.health_status)).length,
    totalCarbon,
    gpsTagged: trees.filter((t) => t.lat && t.lng).length,
  };

  const chartData = [
    { name: "Healthy", count: stats.healthy, color: "#10b981" },
    { name: "Fair", count: stats.fair, color: "#f59e0b" },
    { name: "Poor", count: stats.poor, color: "#ef4444" },
    { name: "Not assessed", count: stats.notAssessed, color: "#94a3b8" },
  ];

  const recentTrees = trees.slice(0, 5);
  const pendingPlantReviews = plantingRecords.filter((item) => item.status === "pending").length;

  return (
    <div className="p-4 sm:p-6 lg:p-8">
      {/* Header */}
      <div className="mb-6 flex flex-col gap-4 sm:mb-8 sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0">
          <h1 className="font-fraunces text-2xl font-semibold text-foreground sm:text-3xl">
            Welcome back, {user?.full_name?.split(" ")[0] || "User"}
          </h1>
          <p className="text-muted-foreground mt-1">
            TreeTrace Geo-Spatial Inventory — Panabo City
          </p>
        </div>
        <Link to="/add-tree" className="w-full sm:w-auto">
          <Button className="flex w-full items-center gap-2 sm:w-auto">
            <Plus className="w-4 h-4" />
            Add Tree
          </Button>
        </Link>
      </div>

      {pendingPlantReviews > 0 && (
        <button
          type="button"
          onClick={() => navigate("/planting?review=pending")}
          className="mb-6 flex w-full items-center justify-between rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-left text-amber-900 transition hover:bg-amber-100"
        >
          <span className="font-medium">{pendingPlantReviews} suggested plant review{pendingPlantReviews === 1 ? "" : "s"} waiting</span>
          <span className="text-sm underline">Review now</span>
        </button>
      )}

      {/* Stats */}
      <div className="mb-8 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatsCard title="Total Trees" value={stats.total} icon={TreePine} color="primary" onClick={() => navigate("/trees")} />
        <StatsCard title="Healthy" value={stats.healthy} icon={Leaf} color="emerald" onClick={() => navigate("/trees?health=Healthy")} />
        <StatsCard title="Need Attention" value={stats.fair + stats.poor}
          subtitle={`${stats.fair} Fair, ${stats.poor} Poor`} icon={AlertTriangle} color="amber" onClick={() => navigate("/trees?health=attention")} />
        <StatsCard title="Carbon Stock" value={formatCarbonKg(stats.totalCarbon)}
          subtitle="Estimated carbon stored" icon={Activity} color="blue" onClick={() => navigate("/trees")} />
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
                <Bar dataKey="count" radius={[6, 6, 0, 0]} onClick={(data) => navigate(`/trees?health=${data.name}`)} cursor="pointer">
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

        <Card className="min-w-0 lg:col-span-2">
          <CardHeader>
            <CardTitle className="font-fraunces text-lg">Estimated Carbon Stock per Barangay</CardTitle>
            <p className="text-sm text-muted-foreground">Totals for recorded trees with estimates, in kilograms of carbon (kg C).</p>
          </CardHeader>
          <CardContent>
            {isLoading ? (
              <p className="text-sm text-muted-foreground">Loading carbon stock…</p>
            ) : isError && !trees.length ? (
              <p className="text-sm text-muted-foreground">Unable to load carbon stock data.</p>
            ) : carbonByBarangay.length === 0 ? (
              <p className="text-sm text-muted-foreground">No carbon stock estimates recorded yet.</p>
            ) : (
              <div className="max-h-56 overflow-y-auto">
                <ResponsiveContainer width="100%" height={Math.max(180, carbonByBarangay.length * 22 + 30)}>
                  <BarChart data={carbonByBarangay} layout="vertical" barCategoryGap="30%" margin={{ right: 20 }}>
                    <XAxis type="number" tick={{ fontSize: 12 }} tickFormatter={(value) => compactCarbonNumber.format(value)} />
                    <YAxis type="category" dataKey="name" width={110} tick={{ fontSize: 12 }} interval={0} />
                    <Tooltip
                      formatter={(value, _name, item) => [
                        `${carbonNumber.format(value)} kg C`,
                        `${item.payload.estimated} of ${item.payload.total} trees with estimates`,
                      ]}
                    />
                    <Bar dataKey="carbonKg" fill="#10b981" radius={[0, 6, 6, 0]} maxBarSize={16} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            )}
          </CardContent>
        </Card>

        {/* Recent Trees */}
        <Card className="lg:col-span-3">
          <CardHeader className="flex flex-row items-center justify-between">
            <CardTitle className="font-fraunces text-lg">Recent Entries</CardTitle>
            <Link to="/trees" className="text-primary text-sm hover:underline">View all</Link>
          </CardHeader>
          <CardContent>
            {isLoading ? (
              <div className="space-y-3">
                {[1, 2, 3].map((i) => (
                  <div key={i} className="h-16 bg-muted rounded-lg animate-pulse" />
                ))}
              </div>
            ) : (
              <div className="space-y-2">
                {recentTrees.map((tree) => (
                  <Link
                    key={tree.id}
                    to={`/trees/${tree.id}`}
                    className="flex flex-col gap-3 rounded-lg p-3 transition-colors hover:bg-muted sm:flex-row sm:items-center sm:justify-between"
                  >
                    <div className="flex min-w-0 items-center gap-3">
                      <div className="flex h-14 w-14 flex-shrink-0 items-center justify-center overflow-hidden rounded-lg bg-primary/10">
                        {tree.photo_url ? (
                          <img
                            src={tree.photo_url}
                            alt={tree.common_name ? `${tree.common_name} tree` : "Tree photo"}
                            className="h-full w-full object-cover"
                            loading="lazy"
                            onError={(event) => {
                              event.currentTarget.style.display = "none";
                              event.currentTarget.nextElementSibling?.classList.remove("hidden");
                            }}
                          />
                        ) : null}
                        <TreePine className={`h-5 w-5 text-primary ${tree.photo_url ? "hidden" : ""}`} />
                      </div>
                      <div className="min-w-0">
                        <p className="truncate text-sm font-medium text-foreground">{tree.common_name}</p>
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
                    <div className="flex flex-shrink-0 items-center justify-between gap-3 sm:justify-end">
                      {tree.carbon_kg && (
                        <span className="text-xs text-muted-foreground">
                          C: {formatCarbonKg(tree.carbon_kg)}
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

      {planting.suggestions?.length > 0 && (
        <Card className="mt-6">
          <CardHeader className="flex flex-row items-center justify-between">
            <CardTitle className="font-fraunces text-lg">Planting Suggestions</CardTitle>
            <Link to="/planting" className="text-primary text-sm hover:underline">Open planner</Link>
          </CardHeader>
          <CardContent>
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              {planting.suggestions.slice(0, 4).map((item) => (
                <button
                  key={`${item.species_name}-${item.recommended_area}`}
                  type="button"
                  onClick={() => navigate("/planting")}
                  className="overflow-hidden rounded-xl border bg-card text-left transition hover:bg-muted/50"
                >
                  <div className="h-28 bg-muted">
                    {item.image_urls?.[0] ? (
                      <img src={item.image_urls[0]} alt={item.species_name} className="h-full w-full object-cover" />
                    ) : (
                      <div className="flex h-full items-center justify-center">
                        <Sprout className="h-8 w-8 text-primary" />
                      </div>
                    )}
                  </div>
                  <div className="p-3">
                    <p className="truncate text-sm font-semibold">{item.species_name}</p>
                    <p className="truncate text-xs text-muted-foreground">{item.recommended_area}</p>
                  </div>
                </button>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

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
                  className="flex flex-col gap-2 rounded-lg bg-muted/50 p-3 sm:flex-row sm:items-center sm:justify-between"
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
                  <div className="flex items-center gap-2 sm:justify-end">
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
