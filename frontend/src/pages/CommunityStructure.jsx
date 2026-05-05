import { useQuery } from "@tanstack/react-query";
import { aiApi } from "@/api/ai";
import EndangeredBadge from "@/components/trees/EndangeredBadge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { MapPin, TreePine, AlertTriangle, Leaf } from "lucide-react";
import {
  BarChart, Bar, XAxis, YAxis, Tooltip,
  ResponsiveContainer, Cell, PieChart, Pie, Legend,
} from "recharts";
import { Link } from "react-router-dom";

const STATUS_COLORS = {
  CR: "#d32f2f",
  EN: "#f57c00",
  VU: "#fbc02d",
  LC: "#388e3c",
  NL: "#9e9e9e",
};

export default function CommunityStructure() {
  const { data, isLoading } = useQuery({
    queryKey: ["community-structure"],
    queryFn:  aiApi.communityStructure,
  });

  if (isLoading) {
    return (
      <div className="p-8">
        <h1 className="font-fraunces text-3xl font-semibold mb-6">Community Structure</h1>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          {[1, 2, 3].map((i) => (
            <div key={i} className="h-28 bg-muted rounded-xl animate-pulse" />
          ))}
        </div>
        <div className="h-64 bg-muted rounded-xl animate-pulse" />
      </div>
    );
  }

  const pieData = (data?.species_distribution || [])
    .slice(0, 8)
    .map((s, i) => ({
      name:  s.name,
      value: s.count,
      fill:  `hsl(${(i * 45) % 360}, 60%, 50%)`,
    }));

  return (
    <div className="p-8">
      <div className="mb-6">
        <h1 className="font-fraunces text-3xl font-semibold">Community Structure</h1>
        <p className="text-muted-foreground mt-1">
          Biodiversity analysis and species distribution across Panabo City
        </p>
      </div>

      {/* Summary stats */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
        <StatCard icon={TreePine} label="Total Trees"   value={data?.total_trees    || 0} color="text-primary" />
        <StatCard icon={Leaf}     label="Species"       value={data?.total_species  || 0} color="text-emerald-600" />
        <StatCard
          icon={AlertTriangle}
          label="Endangered"
          value={data?.total_endangered || 0}
          color="text-red-600"
          sub="CR + EN status"
        />
        <StatCard
          icon={MapPin}
          label="Barangays"
          value={data?.barangay_breakdown?.length || 0}
          color="text-blue-600"
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        {/* Species Distribution Pie */}
        <Card>
          <CardHeader>
            <CardTitle className="font-fraunces text-lg">Species Distribution</CardTitle>
          </CardHeader>
          <CardContent>
            {pieData.length > 0 ? (
              <ResponsiveContainer width="100%" height={260}>
                <PieChart>
                  <Pie
                    data={pieData}
                    cx="50%"
                    cy="50%"
                    outerRadius={90}
                    dataKey="value"
                    label={({ name, percent }) =>
                      `${name} (${(percent * 100).toFixed(0)}%)`
                    }
                    labelLine={false}
                  >
                    {pieData.map((entry, i) => (
                      <Cell key={i} fill={entry.fill} />
                    ))}
                  </Pie>
                  <Tooltip />
                </PieChart>
              </ResponsiveContainer>
            ) : (
              <p className="text-center text-muted-foreground py-12">No trees recorded yet.</p>
            )}
          </CardContent>
        </Card>

        {/* Barangay Bar Chart */}
        <Card>
          <CardHeader>
            <CardTitle className="font-fraunces text-lg">Trees per Barangay</CardTitle>
          </CardHeader>
          <CardContent>
            {data?.barangay_breakdown?.length > 0 ? (
              <ResponsiveContainer width="100%" height={260}>
                <BarChart data={data.barangay_breakdown.slice(0, 8)} layout="vertical">
                  <XAxis type="number" tick={{ fontSize: 11 }} />
                  <YAxis
                    type="category"
                    dataKey="barangay"
                    width={110}
                    tick={{ fontSize: 10 }}
                  />
                  <Tooltip />
                  <Bar dataKey="total_trees" radius={[0, 4, 4, 0]} fill="hsl(var(--primary))" />
                </BarChart>
              </ResponsiveContainer>
            ) : (
              <p className="text-center text-muted-foreground py-12">No data yet.</p>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Endangered Trees List */}
      {data?.endangered_trees?.length > 0 && (
        <Card className="mb-6 border-red-200">
          <CardHeader>
            <CardTitle className="font-fraunces text-lg flex items-center gap-2 text-red-700">
              <AlertTriangle className="w-5 h-5" />
              Endangered Trees — Do Not Cut ({data.endangered_trees.length})
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-2">
              {data.endangered_trees.map((tree) => (
                <Link
                  key={tree.tree_id}
                  to={`/trees/${tree.tree_id}`}
                  className="flex items-center justify-between p-3 rounded-lg hover:bg-muted transition-colors border border-border"
                >
                  <div className="flex items-center gap-3">
                    <div
                      className="w-3 h-3 rounded-full flex-shrink-0"
                      style={{ backgroundColor: tree.iucn_color }}
                    />
                    <div>
                      <p className="font-medium text-sm">{tree.common_name}</p>
                      <p className="text-xs text-muted-foreground italic">{tree.scientific_name}</p>
                      {tree.barangay && (
                        <p className="text-xs text-muted-foreground flex items-center gap-1 mt-0.5">
                          <MapPin className="w-3 h-3" /> {tree.barangay}
                        </p>
                      )}
                    </div>
                  </div>
                  <EndangeredBadge status={tree.status} statusCode={tree.status_code} />
                </Link>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {/* Barangay Detail Table */}
      {data?.barangay_breakdown?.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="font-fraunces text-lg">Barangay Biodiversity Report</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-border text-muted-foreground text-xs">
                    <th className="text-left py-2 pr-4">Barangay</th>
                    <th className="text-right py-2 pr-4">Trees</th>
                    <th className="text-right py-2 pr-4">Species</th>
                    <th className="text-right py-2 pr-4">Endangered</th>
                    <th className="text-right py-2 pr-4">Shannon Index</th>
                    <th className="text-left py-2">Top Species</th>
                  </tr>
                </thead>
                <tbody>
                  {data.barangay_breakdown.map((row) => (
                    <tr key={row.barangay} className="border-b border-border/50 hover:bg-muted/50">
                      <td className="py-2 pr-4 font-medium">{row.barangay}</td>
                      <td className="py-2 pr-4 text-right">{row.total_trees}</td>
                      <td className="py-2 pr-4 text-right">{row.species_count}</td>
                      <td className="py-2 pr-4 text-right">
                        {row.endangered_count > 0 ? (
                          <span className="text-red-600 font-semibold">{row.endangered_count}</span>
                        ) : (
                          <span className="text-muted-foreground">0</span>
                        )}
                      </td>
                      <td className="py-2 pr-4 text-right font-mono text-xs">
                        {row.shannon_index.toFixed(3)}
                      </td>
                      <td className="py-2 text-muted-foreground text-xs">
                        {row.top_species.map((s) => s.name).join(", ")}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}

function StatCard({ icon: Icon, label, value, color, sub }) {
  return (
    <Card className="border-border">
      <CardContent className="p-4 flex items-center gap-3">
        <div className={`w-10 h-10 rounded-lg bg-muted flex items-center justify-center flex-shrink-0`}>
          <Icon className={`w-5 h-5 ${color}`} />
        </div>
        <div>
          <p className="text-2xl font-fraunces font-semibold">{value}</p>
          <p className="text-xs text-muted-foreground">{label}</p>
          {sub && <p className="text-xs text-muted-foreground">{sub}</p>}
        </div>
      </CardContent>
    </Card>
  );
}
