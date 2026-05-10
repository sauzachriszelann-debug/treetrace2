import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import QRCode from "qrcode";
import { treesApi } from "@/api/trees";
import { usersApi } from "@/api/users";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import {
  Building2,
  Crown,
  Download,
  FileText,
  Printer,
  Route,
  TrendingUp,
  Users,
} from "lucide-react";
import { toast } from "sonner";

export default function ReportsAndTools() {
  const [routeParams, setRouteParams] = useState({ barangay: "", health_status: "", limit: 15 });
  const [route, setRoute] = useState(null);

  const { data: labels = [] } = useQuery({
    queryKey: ["qr-print"],
    queryFn: treesApi.qrPrint,
  });

  const { data: trees = [] } = useQuery({
    queryKey: ["report-trees"],
    queryFn: () => treesApi.list({ limit: 1000 }),
  });

  const { data: analytics } = useQuery({
    queryKey: ["role-analytics"],
    queryFn: usersApi.roleAnalytics,
    retry: false,
  });

  const reportSummary = useMemo(() => {
    const health = trees.reduce((acc, tree) => {
      const key = tree.health_status || "Unknown";
      acc[key] = (acc[key] || 0) + 1;
      return acc;
    }, {});
    const barangays = trees.reduce((acc, tree) => {
      const key = tree.barangay || "Unspecified";
      acc[key] = (acc[key] || 0) + 1;
      return acc;
    }, {});
    const species = new Set(trees.map((tree) => tree.common_name).filter(Boolean));
    const totalCarbon = trees.reduce((sum, tree) => sum + Number(tree.carbon_kg || 0), 0);
    const gpsTagged = trees.filter((tree) => tree.lat && tree.lng).length;
    return { health, barangays, speciesCount: species.size, totalCarbon, gpsTagged };
  }, [trees]);

  const money = (value = 0) =>
    `PHP ${Number(value || 0).toLocaleString("en-PH", { maximumFractionDigits: 0 })}`;

  const escapeHtml = (value) =>
    String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");

  const generateQrSheet = async () => {
    if (!labels.length) {
      toast.error("No tree labels are available yet.");
      return;
    }

    const rows = await Promise.all(
      labels.slice(0, 120).map(async (tree) => {
        const url = `${window.location.origin}/public/tree/${tree.id}`;
        return {
          ...tree,
          publicUrl: url,
          qr: await QRCode.toDataURL(url, {
            errorCorrectionLevel: "M",
            margin: 1,
            width: 220,
          }),
        };
      })
    );

    const html = `
      <html>
        <head>
          <title>TreeTrace QR Labels</title>
          <style>
            body { font-family: Arial, sans-serif; padding: 24px; }
            .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 14px; }
            .label { border: 1px solid #222; border-radius: 8px; padding: 12px; min-height: 150px; display: flex; gap: 10px; align-items: center; }
            img { width: 88px; height: 88px; }
            h3 { margin: 0 0 4px; font-size: 14px; }
            p { margin: 2px 0; font-size: 11px; }
            .brand { font-weight: 700; color: #166534; font-size: 12px; }
          </style>
        </head>
        <body>
          <h1>TreeTrace QR Labels</h1>
          <div class="grid">
            ${rows.map((tree) => `
              <div class="label">
                <img src="${tree.qr}" alt="QR code for ${escapeHtml(tree.common_name || `Tree ${tree.id}`)}" />
                <div>
                  <div class="brand">TreeTrace</div>
                  <h3>${escapeHtml(tree.common_name || "Tree")}</h3>
                  <p><em>${escapeHtml(tree.scientific_name || "")}</em></p>
                  <p>ID: ${tree.id}</p>
                  <p>${escapeHtml(tree.barangay || "Panabo City")}</p>
                  <p>${escapeHtml(tree.publicUrl)}</p>
                </div>
              </div>
            `).join("")}
          </div>
          <script>
            function printWhenImagesAreReady() {
              const images = Array.from(document.images);
              if (!images.length) {
                window.print();
                return;
              }
              let loaded = 0;
              const done = () => {
                loaded += 1;
                if (loaded >= images.length) {
                  setTimeout(() => window.print(), 250);
                }
              };
              images.forEach((img) => {
                if (img.complete) done();
                else {
                  img.onload = done;
                  img.onerror = done;
                }
              });
              setTimeout(() => window.print(), 1500);
            }
            window.onload = printWhenImagesAreReady;
          </script>
        </body>
      </html>`;

    const win = window.open("", "_blank");
    if (!win) {
      toast.error("Popup blocked. Please allow popups for TreeTrace and try again.");
      return;
    }
    win.document.write(html);
    win.document.close();
    win.focus();
  };

  const printInventoryReport = () => {
    if (!trees.length) {
      toast.error("No tree data is available for the report yet.");
      return;
    }

    const generatedAt = new Date().toLocaleString();
    const barangayRows = Object.entries(reportSummary.barangays)
      .sort((a, b) => b[1] - a[1])
      .map(([name, count]) => `<tr><td>${escapeHtml(name)}</td><td>${count}</td></tr>`)
      .join("");
    const healthRows = Object.entries(reportSummary.health)
      .map(([name, count]) => `<tr><td>${escapeHtml(name)}</td><td>${count}</td></tr>`)
      .join("");
    const treeRows = trees.slice(0, 250).map((tree) => `
      <tr>
        <td>${tree.id}</td>
        <td>${escapeHtml(tree.common_name)}</td>
        <td><em>${escapeHtml(tree.scientific_name || "")}</em></td>
        <td>${escapeHtml(tree.barangay || "")}</td>
        <td>${escapeHtml(tree.health_status || "")}</td>
        <td>${tree.dbh_cm ?? ""}</td>
        <td>${tree.height_m ?? ""}</td>
        <td>${tree.carbon_kg ? Number(tree.carbon_kg).toFixed(2) : ""}</td>
      </tr>
    `).join("");

    const html = `
      <html>
        <head>
          <title>TreeTrace Inventory Report</title>
          <style>
            @page { margin: 18mm; }
            body { font-family: Arial, sans-serif; color: #122016; }
            .header { border-bottom: 3px solid #166534; padding-bottom: 12px; margin-bottom: 18px; }
            h1 { margin: 0; color: #14532d; font-size: 26px; }
            h2 { color: #14532d; font-size: 16px; margin-top: 24px; }
            p { margin: 4px 0; color: #334155; }
            .grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 10px; margin: 16px 0; }
            .metric { border: 1px solid #cbd5e1; border-radius: 8px; padding: 10px; }
            .metric strong { display: block; font-size: 20px; color: #14532d; }
            table { width: 100%; border-collapse: collapse; margin-top: 8px; font-size: 11px; }
            th, td { border: 1px solid #d9e2dd; padding: 6px; text-align: left; vertical-align: top; }
            th { background: #ecfdf5; color: #14532d; }
            .two { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
            .note { margin-top: 18px; padding: 10px; border-left: 4px solid #f59e0b; background: #fffbeb; }
          </style>
        </head>
        <body>
          <div class="header">
            <h1>TreeTrace Inventory Report</h1>
            <p>Panabo City Tree Inventory and Conservation Monitoring</p>
            <p>Generated: ${escapeHtml(generatedAt)}</p>
          </div>
          <div class="grid">
            <div class="metric"><span>Total Trees</span><strong>${trees.length}</strong></div>
            <div class="metric"><span>Species</span><strong>${reportSummary.speciesCount}</strong></div>
            <div class="metric"><span>GPS Tagged</span><strong>${reportSummary.gpsTagged}</strong></div>
            <div class="metric"><span>Carbon Stored</span><strong>${reportSummary.totalCarbon.toFixed(1)} kg</strong></div>
          </div>
          <div class="two">
            <section>
              <h2>Health Summary</h2>
              <table><thead><tr><th>Status</th><th>Count</th></tr></thead><tbody>${healthRows}</tbody></table>
            </section>
            <section>
              <h2>Barangay Summary</h2>
              <table><thead><tr><th>Barangay</th><th>Count</th></tr></thead><tbody>${barangayRows}</tbody></table>
            </section>
          </div>
          <h2>Inventory List</h2>
          <table>
            <thead>
              <tr>
                <th>ID</th><th>Common Name</th><th>Scientific Name</th><th>Barangay</th>
                <th>Health</th><th>DBH cm</th><th>Height m</th><th>Carbon kg</th>
              </tr>
            </thead>
            <tbody>${treeRows}</tbody>
          </table>
          <div class="note">
            DBH and AI-assisted values should be validated through field measurement when used for formal compliance.
          </div>
          <script>window.onload = () => setTimeout(() => window.print(), 250);</script>
        </body>
      </html>`;

    const win = window.open("", "_blank");
    if (!win) {
      toast.error("Popup blocked. Please allow popups and try again.");
      return;
    }
    win.document.write(html);
    win.document.close();
    win.focus();
  };

  const buildRoute = async () => {
    try {
      const params = {
        limit: routeParams.limit,
        barangay: routeParams.barangay || undefined,
        health_status: routeParams.health_status || undefined,
      };
      const data = await treesApi.routePlan(params);
      setRoute(data);
    } catch {
      toast.error("Failed to build route plan.");
    }
  };

  const downloadInventoryCsv = async () => {
    try {
      const blob = await treesApi.exportInventoryCsv();
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = "treetrace_inventory.csv";
      document.body.appendChild(link);
      link.click();
      link.remove();
      URL.revokeObjectURL(url);
    } catch (err) {
      toast.error(err?.response?.data?.detail || "Failed to download inventory report.");
    }
  };

  return (
    <div className="p-8 max-w-6xl mx-auto">
      <div className="mb-6">
        <h1 className="font-fraunces text-3xl font-semibold">Reports, Revenue, and Field Tools</h1>
        <p className="text-muted-foreground mt-1">
          Export inventory data, print QR labels, show business viability, and plan field visits.
        </p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-4 gap-3 mb-5">
        <Metric label="Total Trees" value={trees.length} />
        <Metric label="Species Recorded" value={reportSummary.speciesCount} />
        <Metric label="GPS Tagged" value={reportSummary.gpsTagged} />
        <Metric label="Carbon Stored" value={`${reportSummary.totalCarbon.toFixed(1)} kg`} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-5">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2"><Download className="w-5 h-5" /> Export Reports</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <p className="text-sm text-muted-foreground">
              Download CSV for Excel or print a clean report that can be saved as PDF from the browser.
            </p>
            <div className="flex flex-wrap gap-2">
              <Button onClick={downloadInventoryCsv}>
                <Download className="w-4 h-4 mr-2" />
                Download Inventory CSV
              </Button>
              <Button variant="outline" onClick={printInventoryReport}>
                <FileText className="w-4 h-4 mr-2" />
                Print / Save PDF Report
              </Button>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2"><Printer className="w-5 h-5" /> QR Printing Layout</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <p className="text-sm text-muted-foreground">
              Generate printable QR labels with the TreeTrace name, species name, tree ID, and public profile link.
            </p>
            <Button onClick={generateQrSheet}>
              <Printer className="w-4 h-4 mr-2" />
              Print QR Labels
            </Button>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2"><TrendingUp className="w-5 h-5" /> Business Model Proof</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="grid grid-cols-2 gap-3 text-sm">
              <Metric label="Pro Users" value={analytics?.business?.pro_users ?? 0} />
              <Metric label="Upgrade Requests" value={analytics?.business?.upgrade_requests ?? 0} />
              <Metric label="Institutional Accounts" value={analytics?.business?.institutional_accounts ?? 0} />
              <Metric label="Estimated Monthly" value={money(analytics?.business?.estimated_monthly_php)} />
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div className="rounded-lg border p-3 bg-emerald-50/60">
                <div className="flex items-center gap-2 text-sm font-semibold text-emerald-800">
                  <Crown className="w-4 h-4" /> Professional
                </div>
                <p className="text-xs text-emerald-700 mt-1">PHP 99/month for active public or research users.</p>
              </div>
              <div className="rounded-lg border p-3 bg-slate-50">
                <div className="flex items-center gap-2 text-sm font-semibold text-slate-800">
                  <Building2 className="w-4 h-4" /> Enterprise
                </div>
                <p className="text-xs text-slate-600 mt-1">PHP 399+/month for LGUs, schools, and barangays.</p>
              </div>
            </div>
            <div className="text-xs text-muted-foreground">
              Roles: {Object.entries(analytics?.by_role || {}).map(([k, v]) => `${k}: ${v}`).join(" | ") || "No data"}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2"><Users className="w-5 h-5" /> User Analytics</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-2 gap-3 text-sm">
              <Metric label="Total Users" value={analytics?.total_users ?? 0} />
              <Metric label="Active Users" value={analytics?.active_users ?? 0} />
              <Metric label="AI Uses Today" value={analytics?.ai_identifications_today ?? 0} />
              <Metric label="Free Users" value={analytics?.by_plan?.free ?? 0} />
            </div>
          </CardContent>
        </Card>

        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle className="flex items-center gap-2"><Route className="w-5 h-5" /> Field Route Planning</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="grid grid-cols-1 md:grid-cols-3 gap-2">
              <Input
                placeholder="Barangay"
                value={routeParams.barangay}
                onChange={(e) => setRouteParams((p) => ({ ...p, barangay: e.target.value }))}
              />
              <Input
                placeholder="Health status"
                value={routeParams.health_status}
                onChange={(e) => setRouteParams((p) => ({ ...p, health_status: e.target.value }))}
              />
              <Input
                type="number"
                min="1"
                max="100"
                value={routeParams.limit}
                onChange={(e) => setRouteParams((p) => ({ ...p, limit: e.target.value }))}
              />
            </div>
            <Button onClick={buildRoute}>Build Route</Button>
            {route && (
              <div className="rounded-lg border p-3 max-h-72 overflow-auto">
                <p className="font-medium text-sm mb-2">
                  {route.total_stops} stops | {route.estimated_distance_km} km estimated
                </p>
                <ol className="space-y-1 text-sm">
                  {route.route.map((stop) => (
                    <li key={stop.tree_id}>
                      {stop.order}. {stop.common_name} | {stop.barangay || "No barangay"} | {stop.leg_km} km
                    </li>
                  ))}
                </ol>
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}

function Metric({ label, value }) {
  return (
    <div className="rounded-lg border bg-muted/30 p-3">
      <p className="text-muted-foreground text-xs">{label}</p>
      <p className="text-xl font-bold">{value}</p>
    </div>
  );
}
