import { useState, useEffect, useRef } from "react";
import { useNavigate } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Select, SelectContent, SelectItem,
  SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { MapPin, Loader2, Upload, X, Sparkles, Ruler } from "lucide-react";
import { storageApi } from "@/api/storage";
import { aiApi } from "@/api/ai";
import { toast } from "sonner";

function calcBiomassCarbon(dbh_cm, height_m) {
  if (!dbh_cm || !height_m) return { biomass: null, carbon: null };
  const rho = 0.6;
  const AGB = 0.0673 * Math.pow(rho * dbh_cm * dbh_cm * height_m, 0.976);
  const carbon = AGB * 0.47;
  return {
    biomass: Math.round(AGB * 100) / 100,
    carbon: Math.round(carbon * 100) / 100,
  };
}

const DBH_REFERENCES = {
  none: {
    label: "No reference",
    hint: "No reference object provided. Estimate using tree shape, surroundings, and visible context only.",
  },
  a4: {
    label: "A4 paper",
    hint: "A standard A4 paper is visible beside the trunk for scale. A4 size is 21.0 by 29.7 cm.",
  },
  phone: {
    label: "Smartphone",
    hint: "A typical smartphone is visible beside the trunk for scale. Estimate the phone width around 7 cm and height around 15 cm.",
  },
  coin: {
    label: "Philippine coin",
    hint: "A Philippine coin is visible beside the trunk for scale. Use it as the closest visible size reference.",
  },
  ruler: {
    label: "Ruler or tape",
    hint: "A ruler, tape measure, or marked measuring tool is visible beside the trunk. Use the visible markings as scale.",
  },
  person: {
    label: "Person nearby",
    hint: "A person is visible near the trunk. Use the person only as an approximate scale reference.",
  },
};

const errorToMessage = (error, fallback = "Request failed. Please try again.") => {
  const detail = error?.response?.data?.detail ?? error?.response?.data?.message ?? error?.message;
  if (!detail) return fallback;
  if (typeof detail === "string") return detail;
  if (Array.isArray(detail)) {
    return detail
      .map((item) => {
        if (typeof item === "string") return item;
        if (item?.msg) return item.msg;
        return JSON.stringify(item);
      })
      .join(" ");
  }
  if (typeof detail === "object") {
    return detail.msg || detail.message || JSON.stringify(detail);
  }
  return String(detail);
};

export default function TreeForm({
  initial = {},
  onSubmit,
  loading,
  submitLabel = "Save Tree Record",
  savingLabel = "Saving…",
}) {
  const navigate = useNavigate();
  const fileRef = useRef(null);
  const [form, setForm] = useState({
    common_name: "",
    scientific_name: "",
    dbh_cm: "",
    height_m: "",
    health_status: "Healthy",
    barangay: "",
    city: "Panabo City",
    province: "Davao del Norte",
    lat: "",
    lng: "",
    notes: "",
    date_recorded: new Date().toISOString().split("T")[0],
    photo_url: "",
    ...initial,
  });

  const [photoFile, setPhotoFile] = useState(null);
  const [photoPreview, setPhotoPreview] = useState(initial.photo_url || null);
  const [gpsLoading, setGpsLoading] = useState(false);
  const [photoLoading, setPhotoLoading] = useState(false);
  const [aiStatus, setAiStatus] = useState(null); // null | "identifying" | "done" | "error" | "estimating"
  const [aiError, setAiError] = useState(null);
  const [computed, setComputed] = useState({ biomass: null, carbon: null });
  const [dbhReference, setDbhReference] = useState("none");
  const [dbhDistance, setDbhDistance] = useState("");
  const [dbhResult, setDbhResult] = useState(null);
  const [circumferenceCm, setCircumferenceCm] = useState("");
  const [aiConservation, setAiConservation] = useState(null);

  useEffect(() => {
    const { biomass, carbon } = calcBiomassCarbon(
      parseFloat(form.dbh_cm),
      parseFloat(form.height_m)
    );
    setComputed({ biomass, carbon });
  }, [form.dbh_cm, form.height_m]);

  const set = (key, val) => setForm((f) => ({ ...f, [key]: val }));

  const calculateDbhFromCircumference = (value) => {
    setCircumferenceCm(value);
    const circumference = parseFloat(value);
    if (!Number.isFinite(circumference) || circumference <= 0) return;
    const dbh = circumference / Math.PI;
    set("dbh_cm", dbh.toFixed(2));
    setDbhResult({
      dbh_cm: Number(dbh.toFixed(2)),
      confidence: "High",
      method: "Manual circumference measurement",
      analysis_notes: "Calculated from circumference measured at breast height using DBH = circumference / pi.",
      distance_estimate_m: null,
      accuracy_note: "High accuracy when circumference is measured with tape at 1.3 meters above ground.",
    });
  };

  // ── Endangered species check ──────────────────────────────────────────────
  const ENDANGERED = {
    "narra": { status: "Endangered", code: "EN", cut: false },
    "pterocarpus indicus": { status: "Endangered", code: "EN", cut: false },
    "almaciga": { status: "Critically Endangered", code: "CR", cut: false },
    "agathis philippinensis": { status: "Critically Endangered", code: "CR", cut: false },
    "molave": { status: "Endangered", code: "EN", cut: false },
    "vitex parviflora": { status: "Endangered", code: "EN", cut: false },
    "ipil": { status: "Endangered", code: "EN", cut: false },
    "intsia bijuga": { status: "Endangered", code: "EN", cut: false },
    "apitong": { status: "Endangered", code: "EN", cut: false },
    "dipterocarpus grandiflorus": { status: "Endangered", code: "EN", cut: false },
    "dao": { status: "Endangered", code: "EN", cut: false },
    "dracontomelon dao": { status: "Endangered", code: "EN", cut: false },
    "kamagong": { status: "Vulnerable", code: "VU", cut: false },
    "diospyros philippinensis": { status: "Vulnerable", code: "VU", cut: false },
    "yakal": { status: "Vulnerable", code: "VU", cut: false },
    "shorea astylosa": { status: "Vulnerable", code: "VU", cut: false },
    "philippine teak": { status: "Critically Endangered", code: "CR", cut: false },
    "tectona philippinensis": { status: "Critically Endangered", code: "CR", cut: false },
    "lauan": { status: "Vulnerable", code: "VU", cut: false },
    "red lauan": { status: "Endangered", code: "EN", cut: false },
    "shorea negrosensis": { status: "Endangered", code: "EN", cut: false },
  };


  const normalizeSpecies = (value) => value?.toLowerCase().trim() || "";
  const endangeredInfo =
    aiConservation ||
    ENDANGERED[normalizeSpecies(form.common_name)] ||
    ENDANGERED[normalizeSpecies(form.scientific_name)];



  // ── Photo select (local preview only, upload happens on save) ──────────────
  const handlePhotoSelect = (e) => {
    const file = e.target.files[0];
    if (!file) return;
    setPhotoFile(file);
    setPhotoPreview(URL.createObjectURL(file));
    set("photo_url", "");
    setAiStatus(null);
    setAiError(null);
    setDbhResult(null);
    setAiConservation(null);
    // ← ADD THIS LINE:
    setTimeout(() => handleAIIdentify(file), 100);
  };

  const removePhoto = () => {
    setPhotoFile(null);
    setPhotoPreview(null);
    set("photo_url", "");
    setAiStatus(null);
    setAiError(null);
    setDbhResult(null);
    setAiConservation(null);
  };

  // ── AI Species Identification ──────────────────────────────────────────────
  const handleAIIdentify = async (fileOverride) => {
    const target = fileOverride || photoFile;
    if (!target) {
      toast.error("Please upload a photo first.");
      return;
    }
    setAiStatus("identifying");
    setAiError(null);
    try {
      const result = await aiApi.identifyFromFile(target);
      const conservation = result.protected || ["CR", "EN", "VU"].includes(result.status_code)
        ? {
            status: result.endangered_status || "Protected",
            code: result.status_code || "EN",
            cut: result.cutting_allowed !== false,
          }
        : null;
      setAiConservation(conservation);

      // Always fill measurements — backend guarantees numeric values
      const dbh = result.estimated_dbh_cm ? String(result.estimated_dbh_cm) : "";
      const height = result.estimated_height_m ? String(result.estimated_height_m) : "";

      if (result.not_identified) {
        // Species unknown — still apply any measurements we got
        setForm((prev) => ({
          ...prev,
          dbh_cm: dbh || prev.dbh_cm,
          height_m: height || prev.height_m,
        }));
        setAiStatus("partial");
        setAiError(
          result.possible_candidates?.length
            ? `Could not identify species. Possible candidates: ${result.possible_candidates.join(", ")}. Please enter the species name manually.`
            : "Could not identify species from this photo. Please enter the species name manually."
        );
      } else {
        setForm((prev) => ({
          ...prev,
          common_name: result.common_name || prev.common_name,
          scientific_name: result.scientific_name || prev.scientific_name,
          dbh_cm: dbh || prev.dbh_cm,
          height_m: height || prev.height_m,
          notes: result.description || prev.notes,
        }));
        setAiStatus("done");
        toast.success(`Identified: ${result.common_name}`);
      }
    } catch (error) {
      if (error?.response?.status === 402) {
        toast.error(error.response.data?.detail || "Free AI limit reached. Upgrade to Pro for unlimited AI identification.", {
          action: {
            label: "Upgrade",
            onClick: () => navigate("/upgrade"),
          },
        });
        setAiStatus(null);
      } else {
        setAiStatus("partial");
        setAiError("Identification request failed. Please enter the species name manually.");
      }
    }
  };

  // ── AI DBH & Height Estimate ───────────────────────────────────────────────
  const handleAIEstimate = async () => {
    if (!photoFile) {
      toast.error("Please upload a photo first.");
      return;
    }
    setAiStatus("estimating");
    setAiError(null);
    try {
      const { file_url } = await storageApi.uploadPhoto(photoFile);
      const result = await aiApi.identifyFromUrl(file_url);
      const dbh = result.estimated_dbh_cm;
      const height = result.estimated_height_m;
      const isDefaultEstimate = Number(dbh) === 25 && Number(height) === 8;

      if (!dbh || isDefaultEstimate) {
        setDbhResult({
          confidence: "Low",
          method: "AI visual estimate unavailable",
          analysis_notes: result.reason || "The AI did not return a photo-specific DBH estimate for this image.",
          distance_estimate_m: null,
          accuracy_note: "Use the manual circumference calculator for accurate DBH.",
        });
        toast.warning("AI could not estimate DBH from this photo. Please use the manual circumference calculator.");
        setAiStatus(null);
        return;
      }

      setForm((prev) => ({
        ...prev,
        dbh_cm: dbh ? String(dbh) : prev.dbh_cm,
        height_m: height ? String(height) : prev.height_m,
      }));

      setDbhResult({
        dbh_cm: dbh,
        height_m: height,
        confidence: result.confidence || "Low",
        method: "AI visual estimate from uploaded photo URL",
        analysis_notes: "The photo was uploaded first, then analyzed by the vision AI for rough DBH and height estimates.",
        distance_estimate_m: null,
        accuracy_note: "+/- 30-50 cm rough visual estimate. Manual circumference is recommended for accurate DBH.",
        fallback: true,
      });
      toast.success(`DBH: ${dbh || "estimated"} cm - AI visual estimate`);
      setAiStatus("done");
    } catch (error) {
      const status = error.response?.status;
      if (status === 401) {
        toast.error("Please log in again before measuring DBH.");
      } else if (status === 413) {
        toast.error("That photo is too large. Please use a smaller image or retake it.");
      } else {
        toast.error(errorToMessage(error, "AI visual estimate failed. Manual circumference is the accurate method."));
      }
      setAiStatus(null);
    }
  };

  // ── GPS ────────────────────────────────────────────────────────────────────
  const captureGPS = () => {
    setGpsLoading(true);
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        set("lat", pos.coords.latitude);
        set("lng", pos.coords.longitude);
        setGpsLoading(false);
        toast.success("GPS coordinates captured!");
      },
      () => {
        setGpsLoading(false);
        toast.error("Could not get GPS location. Please enter manually.");
      },
      { enableHighAccuracy: true }
    );
  };

  // ── Submit ─────────────────────────────────────────────────────────────────
  const handleSubmit = async (e) => {
    e.preventDefault();

    // Upload photo to Supabase if a new file was selected
    let finalPhotoUrl = form.photo_url;
    if (photoFile && !form.photo_url) {
      setPhotoLoading(true);
      try {
        const { file_url } = await storageApi.uploadPhoto(photoFile);
        finalPhotoUrl = file_url;
      } catch {
        toast.error("Photo upload failed. Saving without photo.");
      } finally {
        setPhotoLoading(false);
      }
    }

    const payload = {
      ...form,
      photo_url: finalPhotoUrl || undefined,
      dbh_cm: form.dbh_cm ? parseFloat(form.dbh_cm) : undefined,
      height_m: form.height_m ? parseFloat(form.height_m) : undefined,
      lat: form.lat ? parseFloat(form.lat) : undefined,
      lng: form.lng ? parseFloat(form.lng) : undefined,
      biomass_kg: computed.biomass || undefined,
      carbon_kg: computed.carbon || undefined,
    };
    onSubmit(payload);
  };

  const isAiLoading = aiStatus === "identifying" || aiStatus === "estimating";

  return (
    <form onSubmit={handleSubmit} className="space-y-6">

      {/* ── Tree Photo ── */}
      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <Label>Tree Photo</Label>
          {/* AI Species Identification button — top right of photo section */}
          <Button
            type="button"
            size="sm"
            variant="outline"
            onClick={handleAIIdentify}
            disabled={!photoFile || isAiLoading}
            className="flex items-center gap-1.5 text-xs border-primary/30 text-primary hover:bg-primary/5"
          >
            <Sparkles className="w-3.5 h-3.5" />
            AI species identification
          </Button>
        </div>

        <div className="flex items-start gap-3">
          {/* Photo preview */}
          {photoPreview ? (
            <div className="relative w-24 h-24 rounded-lg overflow-hidden border border-border flex-shrink-0">
              <img src={photoPreview} alt="" className="w-full h-full object-cover" />
              <button
                type="button"
                onClick={removePhoto}
                className="absolute top-1 right-1 w-5 h-5 bg-black/60 rounded-full flex items-center justify-center"
              >
                <X className="w-3 h-3 text-white" />
              </button>
            </div>
          ) : null}

          <div className="flex flex-col gap-2 flex-1">
            {/* Replace / Upload button */}
            <label className="flex items-center gap-2 px-3 py-2 rounded-lg border border-border bg-muted hover:bg-accent cursor-pointer text-sm transition-colors w-fit">
              <Upload className="w-4 h-4" />
              {photoPreview ? "Replace Photo" : "Upload Photo"}
              <input
                ref={fileRef}
                type="file"
                accept="image/*"
                className="hidden"
                onChange={handlePhotoSelect}
              />
            </label>
          </div>
        </div>

        {/* AI Status Messages */}
        {aiStatus === "identifying" && (
          <div className="flex items-center gap-2 text-sm text-muted-foreground bg-muted/50 rounded-lg px-3 py-2.5">
            <Loader2 className="w-4 h-4 animate-spin text-primary flex-shrink-0" />
            <div>
              <p className="font-medium text-foreground">Identifying species...</p>
              <p className="text-xs">Checking TreeTrace AI-assisted identification</p>
            </div>
          </div>
        )}
        {aiStatus === "estimating" && (
          <div className="flex items-center gap-2 text-sm text-muted-foreground bg-muted/50 rounded-lg px-3 py-2.5">
            <Loader2 className="w-4 h-4 animate-spin text-primary flex-shrink-0" />
            <div>
              <p className="font-medium text-foreground">Estimating measurements...</p>
              <p className="text-xs">AI is analyzing trunk size from photo</p>
            </div>
          </div>
        )}
        {aiStatus === "partial" && aiError && (
          <div className="flex items-start gap-2 text-sm bg-amber-50 border border-amber-200 rounded-lg px-3 py-2.5">
            <span className="text-amber-500 mt-0.5 flex-shrink-0">⚠</span>
            <p className="text-amber-800 text-xs">{aiError}</p>
          </div>
        )}
        {aiStatus === "done" && !aiError && (
          <div className="flex items-center gap-2 text-sm text-emerald-600 bg-emerald-50 rounded-lg px-3 py-2">
            <span>✓</span>
            <p>Fields filled from AI analysis. Edit values as needed.</p>
          </div>
        )}
      </div>

      {/* ── Species ── */}

      {/* ── Endangered Warning ── */}
            {endangeredInfo && (
              <div className={`p-4 rounded-xl border-2 flex items-start gap-3 ${
                endangeredInfo.code === "CR" ? "border-red-400 bg-red-50" :
                endangeredInfo.code === "EN" ? "border-orange-400 bg-orange-50" :
                "border-yellow-400 bg-yellow-50"
              }`}>
                <span className="text-2xl flex-shrink-0">
                  {endangeredInfo.code === "CR" ? "⛔" :
                   endangeredInfo.code === "EN" ? "🚫" : "⚠️"}
                </span>
                <div>
                  <p className={`font-bold text-sm ${
                    endangeredInfo.code === "CR" ? "text-red-700" :
                    endangeredInfo.code === "EN" ? "text-orange-700" :
                    "text-yellow-700"
                  }`}>
                    {endangeredInfo.code === "CR" ? "DO NOT CUT — Critically Endangered!" :
                     endangeredInfo.code === "EN" ? "Protected Species — Cutting Prohibited" :
                     "Vulnerable Species — Handle with Care"}
                  </p>
                  <p className="text-xs text-muted-foreground mt-1">
                    {(form.common_name || form.scientific_name || "This species")} is listed as <strong>{endangeredInfo.status}</strong> under DENR DAO 2017-11.
                    {!endangeredInfo.cut && " Cutting or transporting is strictly prohibited without DENR permit."}
                  </p>
                </div>
              </div>
            )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div className="space-y-2">
          <Label htmlFor="common_name">Common Name *</Label>
          <Input
            id="common_name"
            value={form.common_name}
            onChange={(e) => set("common_name", e.target.value)}
            placeholder="e.g., Narra, Mahogany"
            required
          />
        </div>
        <div className="space-y-2">
          <Label htmlFor="scientific_name">Scientific Name</Label>
          <Input
            id="scientific_name"
            value={form.scientific_name}
            onChange={(e) => set("scientific_name", e.target.value)}
            placeholder="e.g., Pterocarpus indicus"
          />
        </div>
      </div>

      {/* ── Measurements ── */}
      <div className="space-y-3 rounded-lg border border-emerald-200 bg-emerald-50/60 p-3">
        <div className="flex flex-col gap-1">
          <Label htmlFor="circumference_cm">Manual DBH Calculator</Label>
          <p className="text-xs text-muted-foreground">
            Measure trunk circumference at 1.3 meters above ground. DBH is calculated automatically.
          </p>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          <div className="space-y-2">
            <Label htmlFor="circumference_cm" className="text-xs text-muted-foreground">
              Circumference at breast height (cm)
            </Label>
            <Input
              id="circumference_cm"
              type="number"
              min="0"
              step="0.01"
              value={circumferenceCm}
              onChange={(e) => calculateDbhFromCircumference(e.target.value)}
              placeholder="e.g., 94.25"
            />
          </div>
          <div className="rounded-md bg-background/80 border border-border px-3 py-2 text-xs text-muted-foreground flex items-center">
            DBH = circumference / pi. This is the recommended field method for accurate records.
          </div>
        </div>
      </div>

      <div className="space-y-3 rounded-lg border border-border bg-muted/30 p-3">
        <div className="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <Label>AI Photo DBH Estimate</Label>
            <p className="text-xs text-muted-foreground">
              Optional estimate. Use a ruler, A4 paper, phone, or known distance for better results.
            </p>
          </div>
          <Button
            type="button"
            size="sm"
            variant="outline"
            onClick={handleAIEstimate}
            disabled={!photoFile || isAiLoading}
            className="flex items-center gap-1.5 text-xs w-fit"
          >
            {aiStatus === "estimating" ? (
              <Loader2 className="w-3.5 h-3.5 animate-spin" />
            ) : (
              <Ruler className="w-3.5 h-3.5" />
            )}
            Measure from Photo
          </Button>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          <div className="space-y-2">
            <Label className="text-xs text-muted-foreground">Visible scale reference</Label>
            <Select value={dbhReference} onValueChange={setDbhReference}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {Object.entries(DBH_REFERENCES).map(([value, option]) => (
                  <SelectItem key={value} value={value}>
                    {option.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label htmlFor="dbh_distance" className="text-xs text-muted-foreground">
              Camera distance, meters
            </Label>
            <Input
              id="dbh_distance"
              type="number"
              min="0"
              step="0.1"
              value={dbhDistance}
              onChange={(e) => setDbhDistance(e.target.value)}
              placeholder="Optional"
            />
          </div>
        </div>
        {dbhResult && (
          <div className="rounded-md bg-background/80 border border-border px-3 py-2 text-xs text-muted-foreground">
            <span className="font-medium text-foreground">
              {dbhResult.confidence || "AI"} confidence
            </span>
            {dbhResult.distance_estimate_m ? ` - estimated distance ${dbhResult.distance_estimate_m} m` : ""}
            {dbhResult.accuracy_note ? ` - ${dbhResult.accuracy_note}` : ""}
          </div>
        )}
      </div>

      {form.dbh_cm && (
        <div className="rounded-lg border border-primary/20 bg-primary/5 px-3 py-2 text-xs text-muted-foreground">
          DBH field is filled. You can still edit it manually before saving.
        </div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div className="space-y-2">
          <Label htmlFor="dbh_cm">DBH (cm)</Label>
          <Input
            id="dbh_cm"
            type="number"
            step="0.01"
            value={form.dbh_cm}
            onChange={(e) => set("dbh_cm", e.target.value)}
            placeholder="Diameter at Breast Height"
          />
        </div>
        <div className="space-y-2">
          <Label htmlFor="height_m">Height (m)</Label>
          <Input
            id="height_m"
            type="number"
            step="0.01"
            value={form.height_m}
            onChange={(e) => set("height_m", e.target.value)}
            placeholder="Estimated height"
          />
        </div>
      </div>

      {/* Carbon preview */}
      {computed.biomass && (
        <div className="p-3 bg-primary/5 border border-primary/20 rounded-lg flex gap-6 text-sm">
          <div>
            <span className="text-muted-foreground">Biomass: </span>
            <span className="font-semibold text-primary">{computed.biomass} kg</span>
          </div>
          <div>
            <span className="text-muted-foreground">Carbon Stock: </span>
            <span className="font-semibold text-primary">{computed.carbon} kg</span>
          </div>
        </div>
      )}

      {/* ── Health & Date ── */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div className="space-y-2">
          <Label>Health Status *</Label>
          <Select value={form.health_status} onValueChange={(v) => set("health_status", v)}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="Healthy">Healthy</SelectItem>
              <SelectItem value="Fair">Fair</SelectItem>
              <SelectItem value="Poor">Poor</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-2">
          <Label htmlFor="date_recorded">Date Recorded</Label>
          <Input
            id="date_recorded"
            type="date"
            value={form.date_recorded}
            onChange={(e) => set("date_recorded", e.target.value)}
          />
        </div>
      </div>

      {/* ── Location ── */}
      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <Label>GPS Location</Label>
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={captureGPS}
            disabled={gpsLoading}
            className="flex items-center gap-2"
          >
            {gpsLoading ? (
              <Loader2 className="w-4 h-4 animate-spin" />
            ) : (
              <MapPin className="w-4 h-4" />
            )}
            {gpsLoading ? "Getting Location…" : "Capture GPS"}
          </Button>
        </div>
        <div className="grid grid-cols-2 gap-3">
          <Input
            placeholder="Latitude"
            value={form.lat}
            onChange={(e) => set("lat", e.target.value)}
            type="number"
            step="any"
          />
          <Input
            placeholder="Longitude"
            value={form.lng}
            onChange={(e) => set("lng", e.target.value)}
            type="number"
            step="any"
          />
        </div>
        <Input
          placeholder="Barangay"
          value={form.barangay}
          onChange={(e) => set("barangay", e.target.value)}
        />
        <div className="grid grid-cols-2 gap-3">
          <Input
            placeholder="City"
            value={form.city}
            onChange={(e) => set("city", e.target.value)}
          />
          <Input
            placeholder="Province"
            value={form.province}
            onChange={(e) => set("province", e.target.value)}
          />
        </div>
      </div>

      {/* ── Notes ── */}
      <div className="space-y-2">
        <Label htmlFor="notes">Notes</Label>
        <Textarea
          id="notes"
          value={form.notes}
          onChange={(e) => set("notes", e.target.value)}
          placeholder="Additional observations…"
          rows={3}
        />
      </div>

      <Button
        type="submit"
        disabled={loading || photoLoading}
        className="w-full flex items-center gap-2"
      >
        {(loading || photoLoading) && <Loader2 className="w-4 h-4 animate-spin" />}
        {photoLoading ? "Uploading photo…" : loading ? savingLabel : submitLabel}
      </Button>
    </form>
  );
}
