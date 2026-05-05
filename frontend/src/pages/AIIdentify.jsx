import { useState, useRef, useCallback } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { aiApi } from "@/api/ai";
import { storageApi } from "@/api/storage";
import { treesApi } from "@/api/trees";
import { useOfflineSync } from "@/hooks/useOfflineSync";
import EndangeredBadge from "@/components/trees/EndangeredBadge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Upload, Loader2, TreePine, AlertTriangle,
  Leaf, Ruler, WifiOff, Plus, RotateCcw, Sparkles, Database, Pencil,
} from "lucide-react";
import { toast } from "sonner";
import { useNavigate } from "react-router-dom";

// ── helpers ───────────────────────────────────────────────────────────────────
const SourceBadge = ({ source }) => {
  if (!source) return null;
  const isPN = source.includes("plantnet");
  return (
    <span className={`inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full ${
      isPN ? "bg-blue-100 text-blue-700" : "bg-purple-100 text-purple-700"
    }`}>
      {isPN ? <Database className="w-3 h-3" /> : <Sparkles className="w-3 h-3" />}
      {source === "plantnet+claude" ? "Pl@ntNet + AI" : source === "plantnet" ? "Pl@ntNet" : "AI Vision"}
    </span>
  );
};

export default function AIIdentify() {
  const navigate                 = useNavigate();
  const qc                       = useQueryClient();
  const { isOnline, addToQueue } = useOfflineSync();
  const fileRef                  = useRef(null);
  const dropRef                  = useRef(null);

  // step: "idle" | "identifying" | "result" | "partial" | "unknown"
  const [step, setStep]         = useState("idle");
  const [preview, setPreview]   = useState(null);
  const [file, setFile]         = useState(null);
  const [result, setResult]     = useState(null);
  const [saving, setSaving]     = useState(false);
  const [isDragging, setIsDragging] = useState(false);

  // editable fields (pre-filled from AI, user can override)
  const [editName, setEditName]         = useState("");
  const [editSci, setEditSci]           = useState("");
  const [editDbh, setEditDbh]           = useState("");
  const [editHeight, setEditHeight]     = useState("");
  const [barangay, setBarangay]         = useState("");
  const [notes, setNotes]               = useState("");

  // ── auto-run identify as soon as a file is chosen ─────────────────────────
  const runIdentify = useCallback(async (f) => {
    if (!f) return;
    if (!isOnline) {
      toast.error("AI identification requires an internet connection.");
      return;
    }
    setStep("identifying");
    setResult(null);
    try {
      const res = await aiApi.identifyFromFile(f);
      setResult(res);

      if (res.not_identified && res.partial) {
        // Both APIs failed but we still have default measurements
        setEditName("");
        setEditSci("");
        setEditDbh(String(res.estimated_dbh_cm ?? 25));
        setEditHeight(String(res.estimated_height_m ?? 8));
        setStep("partial");
      } else if (res.not_identified) {
        setEditName("");
        setEditSci("");
        setEditDbh("25");
        setEditHeight("8");
        setStep("unknown");
      } else {
        // Successful identification — pre-fill editable fields
        setEditName(res.common_name ?? "");
        setEditSci(res.scientific_name ?? "");
        setEditDbh(String(res.estimated_dbh_cm ?? 25));
        setEditHeight(String(res.estimated_height_m ?? 8));
        setNotes(res.description ?? "");
        setStep("result");
      }
    } catch {
      toast.error("Identification request failed. Check your API connection.");
      setStep("idle");
    }
  }, [isOnline]);

  const handleFileSelect = (e) => {
    const f = e.target.files?.[0];
    if (!f) return;
    setFile(f);
    setPreview(URL.createObjectURL(f));
    runIdentify(f);
  };

  // ── drag & drop ────────────────────────────────────────────────────────────
  const handleDrop = (e) => {
    e.preventDefault();
    setIsDragging(false);
    const f = e.dataTransfer.files?.[0];
    if (!f || !f.type.startsWith("image/")) return;
    setFile(f);
    setPreview(URL.createObjectURL(f));
    runIdentify(f);
  };

  // ── save to inventory ──────────────────────────────────────────────────────
  const handleSave = async () => {
    const commonName = editName.trim();
    if (!commonName) {
      toast.error("Please enter a species name before saving.");
      return;
    }
    setSaving(true);
    try {
      let photo_url = null;
      if (isOnline && file) {
        try {
          const up = await storageApi.uploadPhoto(file);
          photo_url = up.file_url;
        } catch {
          toast.warning("Photo upload failed — saving without photo.");
        }
      }

      const payload = {
        common_name:     commonName,
        scientific_name: editSci || undefined,
        health_status:   "Healthy",
        barangay:        barangay || undefined,
        notes:           notes || result?.description || undefined,
        photo_url:       photo_url || undefined,
        dbh_cm:          parseFloat(editDbh) || undefined,
        height_m:        parseFloat(editHeight) || undefined,
      };

      if (isOnline) {
        const tree = await treesApi.create(payload);
        qc.invalidateQueries({ queryKey: ["trees"] });
        toast.success("Tree saved to inventory!");
        navigate(`/trees/${tree.id}`);
      } else {
        addToQueue({ type: "CREATE_TREE", payload });
        toast.success("Saved offline — will sync when connected.");
        reset();
      }
    } catch {
      toast.error("Failed to save tree.");
    } finally {
      setSaving(false);
    }
  };

  // ── submit unknown for expert review ───────────────────────────────────────
  const handleSubmitUnknown = async () => {
    setSaving(true);
    try {
      let photo_url = null;
      if (isOnline && file) {
        try { const up = await storageApi.uploadPhoto(file); photo_url = up.file_url; } catch {}
      }
      if (isOnline) {
        await aiApi.submitUnknown({
          photo_url:       photo_url || "",
          barangay:        barangay || undefined,
          possible_name:   editName || undefined,
          submitter_notes: notes || undefined,
          ai_candidates:   result?.possible_candidates || [],
        });
        toast.success("Submitted for expert review — thank you!");
      } else {
        addToQueue({ type: "SUBMIT_UNKNOWN", payload: { photo_url, barangay, possible_name: editName, submitter_notes: notes } });
      }
      reset();
    } catch {
      toast.error("Submission failed.");
    } finally {
      setSaving(false);
    }
  };

  const reset = () => {
    setStep("idle");
    setPreview(null);
    setFile(null);
    setResult(null);
    setEditName(""); setEditSci(""); setEditDbh(""); setEditHeight("");
    setBarangay(""); setNotes("");
  };

  // ── shared measurement edit row ────────────────────────────────────────────
  const MeasurementRow = () => (
    <div className="grid grid-cols-2 gap-3">
      <div className="space-y-1">
        <Label className="text-xs flex items-center gap-1">
          <Ruler className="w-3 h-3" /> DBH (cm)
        </Label>
        <Input
          type="number"
          min="1"
          value={editDbh}
          onChange={(e) => setEditDbh(e.target.value)}
          placeholder="e.g. 30"
          className="h-8 text-sm"
        />
      </div>
      <div className="space-y-1">
        <Label className="text-xs flex items-center gap-1">
          <Ruler className="w-3 h-3 rotate-90" /> Height (m)
        </Label>
        <Input
          type="number"
          min="1"
          value={editHeight}
          onChange={(e) => setEditHeight(e.target.value)}
          placeholder="e.g. 10"
          className="h-8 text-sm"
        />
      </div>
    </div>
  );

  // ═══════════════════════════════════════════════════════════════════════════
  return (
    <div className="p-8 max-w-4xl mx-auto">
      {/* Header */}
      <div className="mb-6 flex items-start justify-between">
        <div>
          <h1 className="font-fraunces text-3xl font-semibold flex items-center gap-2">
            AI Tree Identifier
            {!isOnline && (
              <span className="flex items-center gap-1 text-sm text-amber-600 font-normal">
                <WifiOff className="w-4 h-4" /> Offline
              </span>
            )}
          </h1>
          <p className="text-muted-foreground mt-1">
            Upload a photo — AI identifies the species, endangered status, and measurements automatically
          </p>
        </div>
        {step !== "idle" && (
          <Button variant="outline" size="sm" onClick={reset} className="flex items-center gap-2">
            <RotateCcw className="w-4 h-4" /> Start Over
          </Button>
        )}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* ── Left: Photo drop zone ── */}
        <div className="space-y-4">
          <Card className="border-border overflow-hidden">
            {/* Drop zone */}
            <div
              ref={dropRef}
              className={`h-72 flex items-center justify-center cursor-pointer transition-colors relative select-none ${
                isDragging ? "bg-primary/10 border-2 border-dashed border-primary" : "bg-muted hover:bg-accent"
              }`}
              onClick={() => fileRef.current?.click()}
              onDragOver={(e) => { e.preventDefault(); setIsDragging(true); }}
              onDragLeave={() => setIsDragging(false)}
              onDrop={handleDrop}
            >
              {preview ? (
                <img src={preview} alt="Tree" className="w-full h-full object-cover" />
              ) : (
                <div className="text-center text-muted-foreground p-6">
                  <TreePine className="w-16 h-16 mx-auto mb-3 opacity-30" />
                  <p className="font-medium">Click or drag a photo here</p>
                  <p className="text-sm mt-1 opacity-70">JPEG, PNG or WebP — AI identifies instantly</p>
                </div>
              )}

              {/* Identifying overlay */}
              {step === "identifying" && (
                <div className="absolute inset-0 bg-black/60 flex items-center justify-center">
                  <div className="text-center text-white">
                    <Loader2 className="w-12 h-12 animate-spin mx-auto mb-3" />
                    <p className="font-semibold text-lg">Analyzing photo…</p>
                    <p className="text-sm opacity-80 mt-1">Checking Pl@ntNet + Claude AI</p>
                  </div>
                </div>
              )}

              {/* Success overlay badge */}
              {step === "result" && (
                <div className="absolute top-3 right-3 bg-emerald-500 text-white text-xs px-2 py-1 rounded-full font-medium shadow">
                  ✓ Identified
                </div>
              )}
              {step === "partial" && (
                <div className="absolute top-3 right-3 bg-amber-500 text-white text-xs px-2 py-1 rounded-full font-medium shadow">
                  Manual entry needed
                </div>
              )}
            </div>

            <input
              ref={fileRef}
              type="file"
              accept="image/*"
              className="hidden"
              onChange={handleFileSelect}
            />

            <CardContent className="p-4 space-y-3">
              {/* Barangay */}
              <div className="space-y-1.5">
                <Label className="text-xs">Barangay (optional)</Label>
                <Input
                  value={barangay}
                  onChange={(e) => setBarangay(e.target.value)}
                  placeholder="e.g., Brgy. San Francisco"
                  className="h-8 text-sm"
                />
              </div>

              {/* Upload button (secondary action — auto-runs on file select) */}
              <Button
                variant="outline"
                className="w-full flex items-center gap-2 text-sm"
                onClick={() => fileRef.current?.click()}
                disabled={step === "identifying"}
              >
                <Upload className="w-4 h-4" />
                {file ? "Change Photo" : "Choose Photo"}
              </Button>
            </CardContent>
          </Card>

          {/* Info card */}
          <Card className="border-dashed border-border">
            <CardContent className="p-4 text-xs text-muted-foreground space-y-1">
              <p className="font-medium text-foreground mb-2">How it works</p>
              <p>✅ Photo is analyzed automatically on upload</p>
              <p>✅ Pl@ntNet botanical DB (500 free/day)</p>
              <p>✅ Claude AI Vision fallback + DBH estimator</p>
              <p>✅ DENR DAO 2017-11 endangered status check</p>
              <p>✅ All fields editable before saving</p>
            </CardContent>
          </Card>
        </div>

        {/* ── Right: Results panel ── */}
        <div className="space-y-4">

          {/* ── IDLE state ── */}
          {step === "idle" && (
            <Card className="border-border border-dashed h-full min-h-[320px]">
              <CardContent className="p-8 text-center text-muted-foreground h-full flex flex-col items-center justify-center">
                <Leaf className="w-14 h-14 mx-auto mb-4 opacity-20" />
                <p className="font-medium text-base">Upload a photo to get started</p>
                <p className="text-sm mt-2 max-w-xs">
                  AI will identify the tree species and estimate measurements as soon as you upload
                </p>
              </CardContent>
            </Card>
          )}

          {/* ── IDENTIFYING state ── */}
          {step === "identifying" && (
            <Card className="border-border h-full min-h-[320px]">
              <CardContent className="p-8 text-center text-muted-foreground h-full flex flex-col items-center justify-center">
                <Loader2 className="w-14 h-14 mx-auto mb-4 animate-spin text-primary opacity-60" />
                <p className="font-medium text-base text-foreground">Identifying species…</p>
                <p className="text-sm mt-2">Querying Pl@ntNet botanical database</p>
                <p className="text-sm">and Claude AI Vision model</p>
              </CardContent>
            </Card>
          )}

          {/* ── RESULT: Successful identification ── */}
          {step === "result" && result && (
            <>
              {/* Endangered warning */}
              {result.protected && (
                <div className={`p-4 rounded-xl border-2 ${
                  result.status_code === "CR" ? "border-red-400 bg-red-50" :
                  result.status_code === "EN" ? "border-orange-400 bg-orange-50" :
                  "border-yellow-400 bg-yellow-50"
                }`}>
                  <div className="flex items-start gap-2">
                    <AlertTriangle className={`w-5 h-5 mt-0.5 flex-shrink-0 ${
                      result.status_code === "CR" ? "text-red-600" :
                      result.status_code === "EN" ? "text-orange-600" : "text-yellow-600"
                    }`} />
                    <div>
                      <p className="font-semibold text-sm">
                        {result.status_code === "CR" ? "⛔ Do NOT cut this tree!" :
                         result.status_code === "EN" ? "🚫 Protected — cutting prohibited" :
                         "⚠️ Vulnerable species — handle with care"}
                      </p>
                      <p className="text-xs mt-0.5 text-muted-foreground">
                        DENR DAO 2017-11. Cutting is{" "}
                        {result.cutting_allowed ? "allowed with permit" : "strictly prohibited"}.
                      </p>
                    </div>
                  </div>
                </div>
              )}

              <Card className="border-border">
                <CardHeader className="pb-3">
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-0.5">
                        <EndangeredBadge status={result.endangered_status} statusCode={result.status_code} />
                        <SourceBadge source={result.source} />
                      </div>
                      <p className="text-xs text-muted-foreground">{result.family}</p>
                    </div>
                    <span className={`text-xs px-2 py-0.5 rounded-full flex-shrink-0 ${
                      result.confidence === "High"   ? "bg-emerald-100 text-emerald-700" :
                      result.confidence === "Medium" ? "bg-amber-100 text-amber-700" :
                      "bg-gray-100 text-gray-700"
                    }`}>
                      {result.confidence} confidence
                    </span>
                  </div>
                </CardHeader>

                <CardContent className="space-y-4 text-sm">
                  {/* Editable name fields */}
                  <div className="space-y-2">
                    <div className="space-y-1">
                      <Label className="text-xs flex items-center gap-1">
                        <Pencil className="w-3 h-3" /> Common Name
                      </Label>
                      <Input
                        value={editName}
                        onChange={(e) => setEditName(e.target.value)}
                        placeholder="Common name"
                        className="font-fraunces font-semibold h-9"
                      />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs">Scientific Name</Label>
                      <Input
                        value={editSci}
                        onChange={(e) => setEditSci(e.target.value)}
                        placeholder="Genus species"
                        className="italic text-muted-foreground h-8 text-sm"
                      />
                    </div>
                  </div>

                  <p className="text-foreground/80 text-xs">{result.description}</p>

                  {/* Measurement fields — always editable */}
                  <div className="p-3 bg-primary/5 rounded-lg border border-primary/10 space-y-2">
                    <p className="text-xs font-medium text-primary/80 flex items-center gap-1">
                      <Ruler className="w-3 h-3" /> AI-Estimated Measurements
                      <span className="text-muted-foreground font-normal ml-1">(edit if needed)</span>
                    </p>
                    <MeasurementRow />
                    {result.plantnet_score && (
                      <p className="text-xs text-muted-foreground">
                        Pl@ntNet match: {(result.plantnet_score * 100).toFixed(1)}%
                      </p>
                    )}
                  </div>

                  {(result.distinguishing_features || result.look_alikes || result.dbh_method) && (
                    <div className="space-y-1 text-xs text-muted-foreground border-t border-border pt-2">
                      {result.distinguishing_features && (
                        <p><span className="font-medium text-foreground">Key features:</span> {result.distinguishing_features}</p>
                      )}
                      {result.look_alikes && (
                        <p><span className="font-medium text-foreground">Look-alikes:</span> {result.look_alikes}</p>
                      )}
                      {result.dbh_method && (
                        <p><span className="font-medium text-foreground">DBH method:</span> {result.dbh_method}</p>
                      )}
                      {result.habitat && (
                        <p><span className="font-medium text-foreground">Habitat:</span> {result.habitat}</p>
                      )}
                    </div>
                  )}

                  <div className="space-y-1">
                    <Label className="text-xs">Additional notes</Label>
                    <Input
                      value={notes}
                      onChange={(e) => setNotes(e.target.value)}
                      placeholder="Any extra observations…"
                      className="h-8 text-sm"
                    />
                  </div>

                  <Button className="w-full flex items-center gap-2" onClick={handleSave} disabled={saving}>
                    {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <Plus className="w-4 h-4" />}
                    {saving ? "Saving…" : "Save to Tree Inventory"}
                    {!isOnline && " (Offline)"}
                  </Button>
                </CardContent>
              </Card>
            </>
          )}

          {/* ── PARTIAL: AI failed but measurements estimated — manual species entry ── */}
          {step === "partial" && (
            <Card className="border-amber-200 bg-amber-50/50">
              <CardHeader className="pb-2">
                <CardTitle className="font-fraunces text-lg flex items-center gap-2 text-amber-800">
                  <AlertTriangle className="w-5 h-5 text-amber-500" />
                  Species Not Identified Automatically
                </CardTitle>
                <p className="text-sm text-amber-700">
                  AI could not identify this species from the photo. Please fill in the species name — measurements have been estimated.
                </p>
              </CardHeader>
              <CardContent className="space-y-4">
                {result?.possible_candidates?.length > 0 && (
                  <div className="bg-white rounded-lg p-3 border border-amber-200">
                    <p className="text-xs font-medium mb-2">Possible candidates (tap to use):</p>
                    <div className="flex flex-wrap gap-2">
                      {result.possible_candidates.map((c, i) => (
                        <button
                          key={i}
                          onClick={() => setEditName(c)}
                          className="text-xs px-2 py-1 bg-amber-100 hover:bg-amber-200 text-amber-800 rounded-full transition-colors"
                        >
                          {c}
                        </button>
                      ))}
                    </div>
                  </div>
                )}

                <div className="space-y-3">
                  <div className="space-y-1">
                    <Label className="text-xs">
                      Common Name <span className="text-red-500">*</span>
                    </Label>
                    <Input
                      value={editName}
                      onChange={(e) => setEditName(e.target.value)}
                      placeholder="e.g., Narra, Mahogany, Acacia…"
                      className="font-medium"
                      autoFocus
                    />
                  </div>
                  <div className="space-y-1">
                    <Label className="text-xs">Scientific Name (optional)</Label>
                    <Input
                      value={editSci}
                      onChange={(e) => setEditSci(e.target.value)}
                      placeholder="e.g., Pterocarpus indicus"
                      className="italic text-sm"
                    />
                  </div>
                  <div className="space-y-1">
                    <Label className="text-xs">Barangay (optional)</Label>
                    <Input
                      value={barangay}
                      onChange={(e) => setBarangay(e.target.value)}
                      placeholder="e.g., Brgy. Kakar"
                      className="text-sm"
                    />
                  </div>

                  <div className="p-3 bg-white rounded-lg border border-amber-200 space-y-2">
                    <p className="text-xs font-medium text-muted-foreground">
                      Estimated Measurements <span className="font-normal">(edit if needed)</span>
                    </p>
                    <MeasurementRow />
                  </div>

                  <div className="space-y-1">
                    <Label className="text-xs">Notes</Label>
                    <Input
                      value={notes}
                      onChange={(e) => setNotes(e.target.value)}
                      placeholder="Location, size, any details…"
                      className="text-sm"
                    />
                  </div>
                </div>

                <div className="flex flex-col gap-2">
                  <Button className="w-full flex items-center gap-2" onClick={handleSave} disabled={saving || !editName.trim()}>
                    {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <Plus className="w-4 h-4" />}
                    {saving ? "Saving…" : "Save to Tree Inventory"}
                  </Button>
                  <Button
                    variant="outline"
                    className="w-full text-sm"
                    onClick={handleSubmitUnknown}
                    disabled={saving}
                  >
                    Submit for Expert Review Instead
                  </Button>
                </div>
              </CardContent>
            </Card>
          )}

          {/* ── UNKNOWN: Truly unidentifiable — expert review ── */}
          {step === "unknown" && result?.not_identified && !result?.partial && (
            <Card className="border-border">
              <CardHeader>
                <CardTitle className="font-fraunces text-lg flex items-center gap-2">
                  <AlertTriangle className="w-5 h-5 text-amber-500" />
                  Species Not Identified
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-4 text-sm">
                <p className="text-muted-foreground">{result.reason}</p>

                {result.possible_candidates?.length > 0 && (
                  <div>
                    <p className="font-medium mb-2 text-xs">Possible candidates:</p>
                    <div className="flex flex-wrap gap-2">
                      {result.possible_candidates.map((c, i) => (
                        <button
                          key={i}
                          onClick={() => setEditName(c)}
                          className="text-xs px-2 py-1 bg-muted hover:bg-accent rounded-full transition-colors"
                        >
                          {c}
                        </button>
                      ))}
                    </div>
                  </div>
                )}

                <div className="space-y-2">
                  <div className="space-y-1">
                    <Label className="text-xs">Your best guess (optional)</Label>
                    <Input value={editName} onChange={(e) => setEditName(e.target.value)} placeholder="Species name if you know it" />
                  </div>
                  <div className="space-y-1">
                    <Label className="text-xs">Notes</Label>
                    <Input value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Location, size, any details…" />
                  </div>
                </div>

                <p className="text-xs text-muted-foreground bg-muted p-3 rounded-lg">
                  Submitting this photo helps improve our AI model. An expert will review and identify the species.
                </p>

                <div className="flex flex-col gap-2">
                  <Button className="w-full flex items-center gap-2" onClick={handleSubmitUnknown} disabled={saving}>
                    {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <Upload className="w-4 h-4" />}
                    {saving ? "Submitting…" : "Submit for Expert Review"}
                  </Button>
                  {editName.trim() && (
                    <Button variant="outline" className="w-full" onClick={handleSave} disabled={saving}>
                      <Plus className="w-4 h-4 mr-2" />
                      Save Anyway with Manual Name
                    </Button>
                  )}
                </div>
              </CardContent>
            </Card>
          )}
        </div>
      </div>
    </div>
  );
}
