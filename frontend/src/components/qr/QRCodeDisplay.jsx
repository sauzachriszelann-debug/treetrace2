import { useEffect, useRef, useState } from "react";
import QRCode from "qrcode";
import { Button } from "@/components/ui/button";
import { Download, Printer } from "lucide-react";

export default function QRCodeDisplay({ tree }) {
    const canvasRef = useRef(null);
    const [dataUrl, setDataUrl] = useState(null);

    const qrData = `${window.location.origin}/public/tree/${tree.id}`;

    useEffect(() => {
        if (!canvasRef.current) return;
        QRCode.toCanvas(canvasRef.current, qrData, {
            width: 200,
            margin: 2,
            color: { dark: "#1a2e1a", light: "#ffffff" }
        }, (err) => {
            if (!err) {
                setDataUrl(canvasRef.current.toDataURL());
            }
        });
    }, [tree.id]);

    const download = () => {
        if (!dataUrl) return;
        const link = document.createElement("a");
        link.download = `TreeTrace-QR-${tree.common_name}-${tree.id}.png`;
        link.href = dataUrl;
        link.click();
    };

    return (
        <div className="flex flex-col items-center gap-4">
            <div className="p-4 bg-white rounded-xl border border-border shadow-sm">
                <canvas ref={canvasRef} className="block" />
                <p className="text-center text-xs text-muted-foreground mt-2 font-mono">{tree.common_name}</p>
                <p className="text-center text-xs text-muted-foreground font-mono">ID: {tree.id?.slice(0, 8)}…</p>
            </div>
            <div className="flex gap-2">
                <Button variant="outline" size="sm" onClick={download} className="flex items-center gap-2">
                    <Download className="w-4 h-4" />
                    Download
                </Button>
                <Button variant="outline" size="sm" onClick={() => window.print()} className="flex items-center gap-2">
                    <Printer className="w-4 h-4" />
                    Print
                </Button>
            </div>
        </div>
    );
}