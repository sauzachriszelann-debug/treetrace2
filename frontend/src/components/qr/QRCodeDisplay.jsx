import { useEffect, useMemo, useRef, useState } from "react";
import QRCode from "qrcode";
import { Button } from "@/components/ui/button";
import { Download, Printer } from "lucide-react";

export default function QRCodeDisplay({ tree }) {
  const canvasRef = useRef(null);
  const [dataUrl, setDataUrl] = useState(null);
  const [error, setError] = useState("");

  const treeId = String(tree?.id ?? "");
  const treeName = tree?.common_name || "Tree";
  const qrData = useMemo(
    () => `${window.location.origin}/public/tree/${treeId}`,
    [treeId],
  );

  useEffect(() => {
    if (!canvasRef.current || !treeId) return;

    setDataUrl(null);
    setError("");
    QRCode.toCanvas(
      canvasRef.current,
      qrData,
      {
        width: 220,
        margin: 2,
        color: { dark: "#123820", light: "#ffffff" },
      },
      (err) => {
        if (err) {
          setError("QR code could not be generated.");
          return;
        }
        setDataUrl(canvasRef.current.toDataURL());
      },
    );
  }, [qrData, treeId]);

  const download = () => {
    if (!dataUrl) return;
    const safeName = treeName.replace(/[^a-z0-9_-]+/gi, "-").replace(/^-|-$/g, "");
    const link = document.createElement("a");
    link.download = `TreeTrace-QR-${safeName || "tree"}-${treeId}.png`;
    link.href = dataUrl;
    link.click();
  };

  return (
    <div className="flex flex-col items-center gap-4">
      <div className="rounded-xl border border-border bg-white p-4 shadow-sm">
        <canvas ref={canvasRef} className="block" />
        {error && (
          <p className="mt-3 max-w-52 text-center text-xs text-destructive">
            {error}
          </p>
        )}
        <p className="mt-3 text-center font-mono text-xs text-muted-foreground">
          {treeName}
        </p>
        <p className="text-center font-mono text-xs text-muted-foreground">
          ID: {treeId.slice(0, 8)}
        </p>
      </div>
      <div className="flex gap-2">
        <Button
          variant="outline"
          size="sm"
          onClick={download}
          disabled={!dataUrl}
          className="flex items-center gap-2"
        >
          <Download className="h-4 w-4" />
          Download
        </Button>
        <Button
          variant="outline"
          size="sm"
          onClick={() => window.print()}
          className="flex items-center gap-2"
        >
          <Printer className="h-4 w-4" />
          Print
        </Button>
      </div>
    </div>
  );
}
