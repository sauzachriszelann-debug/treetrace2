import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import QRCode from "qrcode";
import { treesApi } from "@/api/trees";
import { usersApi } from "@/api/users";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Download, Printer, Route, Users } from "lucide-react";
import { toast } from "sonner";

export default function ReportsAndTools() {
  const [routeParams, setRouteParams] = useState({ barangay: "", health_status: "", limit: 15 });
  const [route, setRoute] = useState(null);

  const { data: labels = [] } = useQuery({
    queryKey: ["qr-print"],
    queryFn: treesApi.qrPrint,
  });

  const { data: analytics } = useQuery({
    queryKey: ["role-analytics"],
    queryFn: usersApi.roleAnalytics,
    retry: false,
  });

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
                <img src="${tree.qr}" alt="QR code for ${tree.common_name || `Tree ${tree.id}`}" />
                <div>
                  <div class="brand">TreeTrace</div>
                  <h3>${tree.common_name || "Tree"}</h3>
                  <p><em>${tree.scientific_name || ""}</em></p>
                  <p>ID: ${tree.id}</p>
                  <p>${tree.barangay || "Panabo City"}</p>
                  <p>${tree.publicUrl}</p>
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
        <h1 className="font-fraunces text-3xl font-semibold">Reports and Field Tools</h1>
        <p className="text-muted-foreground mt-1">
          Export inventory data, print QR labels, view role analytics, and plan field visits.
        </p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-5">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2"><Download className="w-5 h-5" /> Export Reports</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <p className="text-sm text-muted-foreground">
              Download the official tree inventory as CSV for Excel, LGU reports, or DENR-style summaries.
            </p>
            <Button onClick={downloadInventoryCsv}>
              <Download className="w-4 h-4 mr-2" />
              Download Inventory CSV
            </Button>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2"><Printer className="w-5 h-5" /> QR Printing Layout</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <p className="text-sm text-muted-foreground">
              Generate printable QR labels with the TreeTrace logo, species name, tree ID, and public profile link.
            </p>
            <Button onClick={generateQrSheet}>
              <Printer className="w-4 h-4 mr-2" />
              Print QR Labels
            </Button>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2"><Users className="w-5 h-5" /> Role Analytics</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-2 gap-3 text-sm">
              <Metric label="Total Users" value={analytics?.total_users ?? 0} />
              <Metric label="Active Users" value={analytics?.active_users ?? 0} />
              <Metric label="Upgrade Requests" value={analytics?.upgrade_requests ?? 0} />
              <Metric label="AI Uses Today" value={analytics?.ai_identifications_today ?? 0} />
            </div>
            <div className="mt-4 text-xs text-muted-foreground">
              Roles: {Object.entries(analytics?.by_role || {}).map(([k, v]) => `${k}: ${v}`).join(" · ") || "No data"}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2"><Route className="w-5 h-5" /> Field Route Planning</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="grid grid-cols-3 gap-2">
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
                  {route.total_stops} stops · {route.estimated_distance_km} km estimated
                </p>
                <ol className="space-y-1 text-sm">
                  {route.route.map((stop) => (
                    <li key={stop.tree_id}>
                      {stop.order}. {stop.common_name} · {stop.barangay || "No barangay"} · {stop.leg_km} km
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
