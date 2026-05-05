import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { treesApi } from "@/api/trees";
import { storageApi } from "@/api/storage";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Search, QrCode, CheckCircle, Loader2, Download, Printer, TreePine } from "lucide-react";
import { toast } from "sonner";
import QRCode from "qrcode";

export default function QRManager() {
  const qc = useQueryClient();
  const [search, setSearch]           = useState("");
  const [selected, setSelected]       = useState(null);
  const [generating, setGenerating]   = useState(null);
  const [qrDataUrl, setQrDataUrl]     = useState(null);

  const { data: trees = [], isLoading } = useQuery({
    queryKey: ["trees"],
    queryFn: () => treesApi.list({ limit: 500 }),
  });

  const filtered = trees.filter((t) =>
    t.common_name?.toLowerCase().includes(search.toLowerCase()) ||
    t.barangay?.toLowerCase().includes(search.toLowerCase())
  );

  // Select a tree and generate its QR preview
  const selectTree = async (tree) => {
    setSelected(tree);
    // Generate QR preview in memory
    const publicUrl = `${window.location.origin}/public/tree/${tree.id}`;
    try {
      const dataUrl = await QRCode.toDataURL(publicUrl, {
        width: 300,
        margin: 2,
        color: { dark: "#1a1a1a", light: "#ffffff" },
      });
      setQrDataUrl(dataUrl);
    } catch {
      setQrDataUrl(null);
    }
  };

  const generateAndSaveQR = async (tree) => {
    setGenerating(tree.id);
    try {
      const publicUrl = `${window.location.origin}/public/tree/${tree.id}`;
      const dataUrl = await QRCode.toDataURL(publicUrl, {
        width: 512,
        margin: 2,
        color: { dark: "#1a1a1a", light: "#ffffff" },
      });
      const res  = await fetch(dataUrl);
      const blob = await res.blob();
      const { file_url } = await storageApi.uploadQR(blob);
      await treesApi.update(tree.id, { qr_code_url: file_url });
      qc.invalidateQueries({ queryKey: ["trees"] });

      // Update selected if same tree
      if (selected?.id === tree.id) {
        setSelected({ ...tree, qr_code_url: file_url });
        setQrDataUrl(file_url);
      }
      toast.success(`QR code generated for ${tree.common_name}`);
    } catch {
      toast.error("Failed to generate QR code. Check Supabase configuration.");
    } finally {
      setGenerating(null);
    }
  };

  const downloadQR = () => {
    if (!qrDataUrl || !selected) return;
    const link = document.createElement("a");
    link.download = `TreeTrace-QR-${selected.common_name}-${selected.id?.slice?.(0, 8) ?? selected.id}.png`;
    link.href = qrDataUrl;
    link.click();
  };

  const statusColor = (s) =>
    s === "Healthy" ? "bg-emerald-100 text-emerald-700 border-emerald-200"
    : s === "Fair"  ? "bg-amber-100 text-amber-700 border-amber-200"
    :                  "bg-red-100 text-red-700 border-red-200";

  const statusDot = (s) =>
    s === "Healthy" ? "bg-emerald-500"
    : s === "Fair"  ? "bg-amber-500"
    :                  "bg-red-500";

  return (
    <div className="p-8">
      <div className="mb-6">
        <h1 className="font-fraunces text-3xl font-semibold flex items-center gap-3">
          <QrCode className="w-7 h-7" />
          QR Code Manager
        </h1>
        <p className="text-muted-foreground mt-1">
          Generate and print QR codes for tree traceability
        </p>
      </div>

      <div className="flex gap-6" style={{ height: "calc(100vh - 200px)" }}>
        {/* ── Left: Tree list ── */}
        <div className="w-80 flex flex-col flex-shrink-0 bg-card border border-border rounded-xl overflow-hidden shadow-sm">
          {/* Search */}
          <div className="p-3 border-b border-border">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
              <Input
                className="pl-9 h-9 text-sm"
                placeholder="Search trees..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
            </div>
          </div>

          {/* Tree rows */}
          <div className="flex-1 overflow-y-auto">
            {isLoading ? (
              <div className="flex items-center justify-center h-32 text-muted-foreground text-sm">
                <Loader2 className="w-5 h-5 animate-spin mr-2" /> Loading…
              </div>
            ) : filtered.length === 0 ? (
              <div className="flex items-center justify-center h-32 text-muted-foreground text-sm">
                No trees found
              </div>
            ) : (
              filtered.map((tree) => (
                <button
                  key={tree.id}
                  onClick={() => selectTree(tree)}
                  className={`w-full flex items-center gap-3 px-4 py-3 text-left border-b border-border/50 hover:bg-accent transition-colors ${
                    selected?.id === tree.id ? "bg-accent border-l-2 border-l-primary" : ""
                  }`}
                >
                  {/* Tree photo thumbnail */}
                  <div className="w-10 h-10 rounded-lg overflow-hidden flex-shrink-0 bg-muted">
                    {tree.photo_url ? (
                      <img src={tree.photo_url} alt={tree.common_name} className="w-full h-full object-cover" />
                    ) : (
                      <div className="w-full h-full flex items-center justify-center">
                        <TreePine className="w-5 h-5 text-muted-foreground/50" />
                      </div>
                    )}
                  </div>

                  <div className="flex-1 min-w-0">
                    <p className="font-medium text-sm truncate">{tree.common_name}</p>
                    <p className="text-xs text-muted-foreground truncate">
                      {tree.barangay || "No location"}
                    </p>
                  </div>

                  <span className={`text-xs px-2 py-0.5 rounded-full border font-medium flex-shrink-0 flex items-center gap-1 ${statusColor(tree.health_status)}`}>
                    <span className={`w-1.5 h-1.5 rounded-full ${statusDot(tree.health_status)}`} />
                    {tree.health_status}
                  </span>
                </button>
              ))
            )}
          </div>
        </div>

        {/* ── Right: QR panel ── */}
        <div className="flex-1 bg-card border border-border rounded-xl shadow-sm overflow-auto">
          {selected ? (
            <div className="p-8 flex flex-col items-center justify-start h-full">
              {/* Tree photo + info */}
              <div className="w-full max-w-sm">
                {selected.photo_url && (
                  <div className="w-full h-48 rounded-xl overflow-hidden mb-4 border border-border">
                    <img
                      src={selected.photo_url}
                      alt={selected.common_name}
                      className="w-full h-full object-cover"
                    />
                  </div>
                )}

                <h2 className="font-fraunces text-2xl font-semibold text-center mb-1">
                  {selected.common_name}
                </h2>
                {selected.scientific_name && (
                  <p className="text-muted-foreground italic text-sm text-center mb-4">
                    {selected.scientific_name}
                  </p>
                )}

                {/* QR Code */}
                <div className="flex flex-col items-center gap-4 p-6 bg-white rounded-xl border border-border shadow-sm">
                  {qrDataUrl ? (
                    <img
                      src={selected.qr_code_url || qrDataUrl}
                      alt="QR Code"
                      className="w-44 h-44 object-contain"
                    />
                  ) : (
                    <div className="w-44 h-44 bg-muted rounded-lg flex items-center justify-center">
                      <QrCode className="w-16 h-16 text-muted-foreground/30" />
                    </div>
                  )}
                  <div className="text-center">
                    <p className="font-medium text-sm">{selected.common_name}</p>
                    <p className="text-xs text-muted-foreground font-mono">
                      ID: {String(selected.id).slice(0, 8)}…
                    </p>
                  </div>
                </div>

                {/* Actions */}
                <div className="flex gap-2 mt-4">
                  <Button
                    variant="outline"
                    className="flex-1 flex items-center gap-2"
                    onClick={downloadQR}
                    disabled={!qrDataUrl}
                  >
                    <Download className="w-4 h-4" /> Download
                  </Button>
                  <Button
                    variant="outline"
                    className="flex-1 flex items-center gap-2"
                    onClick={() => window.print()}
                  >
                    <Printer className="w-4 h-4" /> Print
                  </Button>
                </div>

                <Button
                  className="w-full mt-2 flex items-center gap-2"
                  onClick={() => generateAndSaveQR(selected)}
                  disabled={generating === selected.id}
                >
                  {generating === selected.id ? (
                    <Loader2 className="w-4 h-4 animate-spin" />
                  ) : (
                    <QrCode className="w-4 h-4" />
                  )}
                  {generating === selected.id
                    ? "Generating…"
                    : selected.qr_code_url
                    ? "Regenerate & Save"
                    : "Generate & Save QR"}
                </Button>

                <p className="text-xs text-muted-foreground text-center mt-3 px-4">
                  Scan this QR code to instantly view the tree's profile, health history, and GPS location.
                </p>
              </div>
            </div>
          ) : (
            <div className="flex items-center justify-center h-full text-muted-foreground">
              <div className="text-center">
                <QrCode className="w-16 h-16 mx-auto mb-4 opacity-20" />
                <p className="font-medium">Select a tree to generate its QR code</p>
                <p className="text-sm mt-1">Choose from the list on the left</p>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
