import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Html5Qrcode } from "html5-qrcode";
import { ScanLine, X, CheckCircle2, QrCode } from "lucide-react";
import { Button } from "@/components/ui/button";
import { toast } from "sonner";

export default function ScanQR() {
  const navigate           = useNavigate();
  const scannerRef         = useRef(null);
  const [scanning, setScanning]   = useState(false);
  const [error, setError]         = useState(null);
  const [lastResult, setLastResult] = useState(null);

  useEffect(() => {
    return () => {
      if (scannerRef.current) {
        scannerRef.current.stop().catch(() => {});
      }
    };
  }, []);

  const startScan = async () => {
    setError(null);
    try {
      const html5Qr = new Html5Qrcode("qr-reader");
      scannerRef.current = html5Qr;
      setScanning(true);

      await html5Qr.start(
        { facingMode: "environment" },
        { fps: 10, qrbox: { width: 260, height: 260 } },
        (decodedText) => {
          setLastResult(decodedText);
          html5Qr.stop().catch(() => {});
          setScanning(false);
          handleQRResult(decodedText);
        },
        () => {} // silent scan errors
      );
    } catch {
      setScanning(false);
      setError("Camera access denied. Please allow camera permission and try again.");
    }
  };

  const stopScan = async () => {
    if (scannerRef.current) {
      await scannerRef.current.stop().catch(() => {});
    }
    setScanning(false);
  };

  const handleQRResult = (text) => {
    try {
      const url = new URL(text);
      const pathname = url.pathname;

      // Match UUID or integer tree IDs from either route style
      // e.g. /public/tree/69e2e7f4-xxxx  or /trees/123  or /public/tree/123
      const match =
        pathname.match(/\/public\/tree\/([a-zA-Z0-9-]+)/) ||
        pathname.match(/\/trees\/([a-zA-Z0-9-]+)/);

      if (match) {
        const treeId = match[1];
        toast.success("Tree identified!");
        navigate(`/public/tree/${treeId}`);
      } else {
        toast.info(`QR content: ${text}`);
      }
    } catch {
      // Not a URL — maybe raw tree ID
      if (text && text.trim().length > 0) {
        toast.info(`QR content: ${text}`);
      }
    }
  };

  return (
    <div className="p-8 max-w-lg mx-auto">
      <div className="mb-6">
        <h1 className="font-fraunces text-3xl font-semibold">QR Scanner</h1>
        <p className="text-muted-foreground mt-1">
          Scan a tree's QR code to view its profile
        </p>
      </div>

      <div className="bg-card border border-border rounded-xl overflow-hidden shadow-sm">
        {/* Camera viewport */}
        <div
          id="qr-reader"
          className="w-full bg-black"
          style={{ minHeight: 300 }}
        />

        <div className="p-6 space-y-4">
          {error && (
            <div className="flex items-start gap-2 text-sm text-destructive bg-destructive/10 p-3 rounded-lg">
              <X className="w-4 h-4 mt-0.5 flex-shrink-0" />
              {error}
            </div>
          )}

          {!scanning ? (
            <Button
              className="w-full flex items-center gap-2"
              onClick={startScan}
            >
              <ScanLine className="w-4 h-4" />
              Start Scanning
            </Button>
          ) : (
            <Button
              variant="outline"
              className="w-full"
              onClick={stopScan}
            >
              Stop Scanner
            </Button>
          )}

          {scanning && (
            <p className="text-center text-muted-foreground text-sm animate-pulse">
              Point camera at a TreeTrace QR code…
            </p>
          )}

          {lastResult && (
            <div className="flex items-center gap-2 text-xs text-muted-foreground bg-muted p-2 rounded-lg">
              <CheckCircle2 className="w-4 h-4 text-emerald-500 flex-shrink-0" />
              <span className="break-all">Last scan: {lastResult}</span>
            </div>
          )}
        </div>
      </div>

      <div className="mt-6 text-center">
        <p className="text-sm text-muted-foreground">
          QR codes are generated in the{" "}
          <a href="/qr-manager" className="text-primary hover:underline">
            QR Manager
          </a>{" "}
          by an admin.
        </p>
      </div>
    </div>
  );
}
