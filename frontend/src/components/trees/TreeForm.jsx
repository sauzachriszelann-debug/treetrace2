import { useState, useEffect, useRef, useCallback } from "react";
import { usePhotoUrl } from "@/lib/usePhotoUrl";
import TreePhotoPreview from "@/components/trees/TreePhotoPreview";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Select, SelectContent, SelectItem,
  SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { MapPin, Loader2, Upload, X, Sparkles } from "lucide-react";
import { storageApi } from "@/api/storage";
import { aiApi } from "@/api/ai";
import { treesApi } from "@/api/trees";
import { toast } from "sonner";
import TreeHeightCalculator from "@/components/trees/TreeHeightCalculator";
import GalleryTreePredictions from "@/components/trees/GalleryTreePredictions";

import { appendMeasurementNote, splitMeasurementNote } from "@/lib/measurementNotes";

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

const usefulAiNote = (description) => {
  const text = (description || "").trim();
  if (!text) return "";
  const lower = text.toLowerCase();
  const blocked = [
    "detailed treetrace vision enrichment is unavailable",
    "identified using plantnet botanical image matching",
    "gemini details are temporarily unavailable",
    "species match is based on plantnet",
  ];
  return blocked.some((phrase) => lower.includes(phrase)) ? "" : text;
};

export default function TreeForm({
  initial = {},
  onSubmit,
  loading,
  submitLabel = "Save Tree Record",
  editLayout = false,
  compactSubmit = false,
  savingLabel = "Saving…",
  photoUploadPurpose = "tree_photo",
}) {
  const fileRef = useRef(null);
  const identificationRequest = useRef(0);
  const currentPhoto = useRef(null);
  const aiFilled = useRef({});
  const [identifiedSpecies, setIdentifiedSpecies] = useState("");
  const [savedEstimate] = useState(() => splitMeasurementNote(initial.notes));
  const [form, setForm] = useState({
    common_name: "",
    scientific_name: "",
    dbh_cm: "",
    height_m: "",
    health_status: "Not assessed",
    barangay: "",
    city: "Panabo City",
    province: "Davao del Norte",
    lat: "",
    lng: "",
    date_recorded: new Date().toISOString().split("T")[0],
    photo_url: "",
    ...initial,
    notes: savedEstimate.notes,
  });

  const [photoFile, setPhotoFile] = useState(null);
  const localPhotoUrl = usePhotoUrl(photoFile);
  const photoPreview = photoFile ? localPhotoUrl : form.photo_url;
  const [gpsLoading, setGpsLoading] = useState(false);
  const [gpsLookup, setGpsLookup] = useState(null);
  const [photoLoading, setPhotoLoading] = useState(false);
  const [aiStatus, setAiStatus] = useState(null); // null | "identifying" | "done" | "error" | "estimating"
  const [aiError, setAiError] = useState(null);
  const [unknownReview, setUnknownReview] = useState(null);
  const [unknownCandidate, setUnknownCandidate] = useState(null);
  const [unknownDialogOpen, setUnknownDialogOpen] = useState(false);
  const [unknownAnalysisSlot, setUnknownAnalysisSlot] = useState(null);
  const [photoAnalysisPending, setPhotoAnalysisPending] = useState(false);
  const [speciesPrediction, setSpeciesPrediction] = useState(null);
  const [comparisonEnabled, setComparisonEnabled] = useState(false);
  const [comparison, setComparison] = useState(null);

  useEffect(() => {
    let active = true;
    async function checkModelTrial() {
      try {
        const status = await aiApi.speciesModelStatus();
        if (active) setComparisonEnabled(status.trial === true && status.ready === true);
      } catch {
        if (active) setComparisonEnabled(false);
      }
    }
    void checkModelTrial();
    return () => { active = false; };
  }, []);
  const [roboflowCandidate, setRoboflowCandidate] = useState(null);
  const [computed, setComputed] = useState({ biomass: null, carbon: null });
  const [aiConservation, setAiConservation] = useState(null);
  const originalMeasurements = useRef({
    dbh_cm: initial.dbh_cm,
    height_m: initial.height_m,
  });
  const [measurementErrors, setMeasurementErrors] = useState({
    dbh_cm: null,
    height_m: null,
  });

  useEffect(() => {
    return () => { identificationRequest.current++; };
  }, []);

  useEffect(() => {
    const { biomass, carbon } = calcBiomassCarbon(
      parseFloat(form.dbh_cm),
      parseFloat(form.height_m)
    );
    setComputed({ biomass, carbon });
  }, [form.dbh_cm, form.height_m]);

  const set = (key, val) => {
    if (key === 'dbh_cm' || key === 'height_m') delete aiFilled.current[key];
    setForm((f) => ({ ...f, [key]: val }));
    if (key === "dbh_cm" || key === "height_m") {
      setMeasurementErrors((errors) => ({ ...errors, [key]: null }));
    }
  };

  const fillDimensions = useCallback(({ dbhCm, heightM }) => {
    setForm(previous => {
      const next = { ...previous };
      for (const [key, value] of [['dbh_cm', dbhCm], ['height_m', heightM]]) {
        const automatic = aiFilled.current[key] !== undefined && Number(previous[key]) === aiFilled.current[key];
        if (String(previous[key] ?? '').trim() !== '' && !automatic) continue;
        const valid = typeof value === 'number' && Number.isFinite(value) && value > 0;
        next[key] = valid ? String(value) : '';
        if (valid) aiFilled.current[key] = value;
        else delete aiFilled.current[key];
      }
      return next.dbh_cm === previous.dbh_cm && next.height_m === previous.height_m ? previous : next;
    });
  }, []);

  const clearAutomaticDimensions = () => {
    const old = { ...aiFilled.current };
    aiFilled.current = {};
    setForm(previous => ({
      ...previous,
      ...Object.fromEntries(Object.entries(old).filter(([key, value]) => Number(previous[key]) === value).map(([key]) => [key, ''])),
    }));
  };

  const getMeasurementUpdate = (key, label) => {
    const value = String(form[key] ?? "").trim();
    const originalValue = originalMeasurements.current[key];
    const hasOriginalValue = originalValue !== null &&
      originalValue !== undefined &&
      String(originalValue).trim() !== "";

    if (!value) {
      return {
        value: undefined,
        error: hasOriginalValue
          ? `Restore the existing ${label} or enter a new positive measurement.`
          : null,
      };
    }

    const parsed = Number(value);
    if (!Number.isFinite(parsed) || parsed <= 0) {
      return { value: undefined, error: `Enter a positive ${label}.` };
    }

    const originalNumber = Number(originalValue);
    const isUnchanged = hasOriginalValue &&
      Number.isFinite(originalNumber) &&
      parsed === originalNumber;

    return { value: isUnchanged ? undefined : parsed, error: null };
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
    currentPhoto.current = file;
    setUnknownReview(null);
    setUnknownCandidate(null);
    setUnknownDialogOpen(false);
    setSpeciesPrediction(null);
    setComparison(null);
    clearAutomaticDimensions();
    setIdentifiedSpecies("");
    setPhotoFile(file);
    set("photo_url", "");
    setRoboflowCandidate(null);
    setAiStatus(null);
    setAiError(null);
    setAiConservation(null);
    void handleAIIdentify(file);
  };

  const removePhoto = () => {
    clearAutomaticDimensions();
    identificationRequest.current++;
    currentPhoto.current = null;
    setUnknownReview(null);
    setUnknownCandidate(null);
    setUnknownDialogOpen(false);
    setSpeciesPrediction(null);
    setComparison(null);
    setIdentifiedSpecies("");
    setPhotoFile(null);
    set("photo_url", "");
    setAiStatus(null);
    setAiError(null);
    setRoboflowCandidate(null);
    setAiConservation(null);
  };

  // ── AI Species Identification ──────────────────────────────────────────────
  const handleCompareModels = async () => {
    const photo = currentPhoto.current;
    if (!photo) return;
    setComparison({ loading: true });
    try {
      const result = await aiApi.compareSpeciesModels(photo);
      if (photo === currentPhoto.current) setComparison(result);
    } catch (error) {
      if (photo === currentPhoto.current) {
        const detail = error?.response?.data?.detail;
        setComparison({
          error: typeof detail === "string" && detail
            ? detail
            : "Could not compare the models. Try uploading the photo again.",
        });
      }
    }
  };

  const handleAIIdentify = async (fileOverride) => {
    const target = fileOverride || photoFile;
    if (!fileOverride && (unknownReview === "submitting" || unknownReview === "submitted")) return;
    if (!target) {
      toast.error("Please upload a photo first.");
      return;
    }
    setAiStatus("identifying");
    setSpeciesPrediction(null);
    const request = ++identificationRequest.current;
    setRoboflowCandidate(null);
    setAiError(null);
    try {
      const result = await aiApi.identifyFromFile(target);
      if (request !== identificationRequest.current || target !== currentPhoto.current) return;
      const needsUnknownReview = !editLayout && result.not_identified && result.below_confidence_threshold;
      const candidate = needsUnknownReview ? result.suggested_species : null;
      setUnknownCandidate(candidate);
      setUnknownReview(needsUnknownReview ? "ready" : null);
      setUnknownDialogOpen(Boolean(needsUnknownReview));
      setIdentifiedSpecies(result.not_identified ? "" : result.scientific_name || "");
      setRoboflowCandidate(
        result.roboflow_candidate?.source === "roboflow_efficientnet"
          ? result.roboflow_candidate
          : null
      );
      const conservation = result.protected || ["CR", "EN", "VU"].includes(result.status_code)
        ? {
          status: result.endangered_status || "Protected",
          code: result.status_code || "EN",
          cut: result.cutting_allowed !== false,
        }
        : null;
      setAiConservation(conservation);

      if (result.not_identified) {
        setAiStatus("partial");
        setAiError(
          needsUnknownReview
            ? `Top AI suggestion: ${candidate?.common_name || candidate?.scientific_name || "Unavailable"} (${result.confidence_percent}% confidence). Below the 75% cutoff. Submit the photo for expert review.`
            : result.source === "local_efficientnet_b0_trial"
            ? `Local model could not confirm the species (top score: ${result.confidence_percent}%). Try a clear photo of the leaves or enter the species manually.`
            : result.possible_candidates?.length
            ? `Could not identify species. Possible candidates: ${result.possible_candidates.join(", ")}. Please enter the species name manually.`
            : "Could not identify species from this photo. Please enter the species name manually."
        );
      } else {
        setForm((prev) => ({
          ...prev,
          common_name: result.common_name || prev.common_name,
          scientific_name: result.scientific_name || prev.scientific_name,
          notes: usefulAiNote(result.description) || prev.notes,
        }));
        setSpeciesPrediction({
          name: result.common_name || result.scientific_name,
          confidence: Number.isFinite(result.confidence_percent)
            ? `${result.confidence_percent}%`
            : result.confidence,
        });
        setAiStatus("done");
        toast.success(`Identified: ${result.common_name}`);
      }
    } catch (error) {
      if (request !== identificationRequest.current || target !== currentPhoto.current) return;
      setAiStatus("partial");
      setAiError("Identification request failed. Please enter the species name manually.");
    }
  };

  // ── GPS ────────────────────────────────────────────────────────────────────
  const captureGPS = () => {
    if (!navigator.geolocation) {
      toast.error("GPS is unavailable in this browser.");
      return;
    }
    setGpsLoading(true);
    navigator.geolocation.getCurrentPosition(
      async ({ coords }) => {
        const { latitude: lat, longitude: lng, accuracy: accuracy_m } = coords;
        setGpsLookup(null);
        setForm(previous => ({ ...previous, lat, lng, barangay: "", city: "", province: "" }));
        try {
          const location = await treesApi.barangayLocation({ lat, lng, accuracy_m });
          setGpsLookup({ lat, lng, status: location.status });
          if (location.status === "resolved") {
            const { barangay, city, province } = location;
            setForm(previous => previous.lat === lat && previous.lng === lng
              ? { ...previous, barangay, city, province }
              : previous);
            toast.success(`Location filled: ${barangay}, ${city}`);
          } else if (location.status === "outside_panabo") {
            toast.error("This location is outside the Panabo City inventory area.");
          } else if (location.status === "uncertain") {
            toast.warning("Barangay uncertain. Please capture GPS again.");
          } else {
            toast.warning("GPS captured. Barangay lookup is unavailable.");
          }
        } catch {
          toast.warning("GPS captured. Barangay lookup is unavailable.");
        } finally {
          setGpsLoading(false);
        }
      },
      () => {
        setGpsLoading(false);
        toast.error("Could not get GPS location. Please enter manually.");
      },
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 }
    );
  };

  // ── Submit ─────────────────────────────────────────────────────────────────
  const submitUnknownPhoto = async () => {
    if (unknownReview !== "ready" || !photoFile || photoAnalysisPending || gpsLoading) return;
    const latitude = String(form.lat ?? "").trim();
    const longitude = String(form.lng ?? "").trim();
    if (latitude || longitude) {
      if (!latitude || !longitude || !Number.isFinite(Number(latitude)) ||
          !Number.isFinite(Number(longitude)) || Math.abs(Number(latitude)) > 90 ||
          Math.abs(Number(longitude)) > 180) {
        toast.error("Enter valid latitude and longitude, or leave both blank.");
        return;
      }
    }
    if (!navigator.onLine) {
      toast.error("Reconnect to submit this photo for expert review.");
      return;
    }
    const dbh = getMeasurementUpdate("dbh_cm", "DBH measurement");
    const height = getMeasurementUpdate("height_m", "height measurement");
    if (dbh.error || height.error) {
      setMeasurementErrors({ dbh_cm: dbh.error, height_m: height.error });
      setUnknownDialogOpen(false);
      toast.error(dbh.error || height.error);
      return;
    }
    setUnknownReview("submitting");
    try {
      let photoUrl = form.photo_url;
      if (!photoUrl) {
        const { file_url } = await storageApi.uploadPhoto(photoFile, "unknown_species");
        if (!file_url) throw new Error("Missing uploaded photo URL");
        photoUrl = file_url;
        set("photo_url", photoUrl);
      }
      await aiApi.submitUnknown({
        photo_url: photoUrl,
        dbh_cm: dbh.value,
        height_m: height.value,
        barangay: form.barangay || undefined,
        location_description: latitude ? `${latitude}, ${longitude}` : undefined,
        submitter_notes: form.notes || undefined,
        ai_candidates: unknownCandidate ? [unknownCandidate] : [],
      });
      setUnknownReview("submitted");
      setUnknownDialogOpen(false);
      toast.success("Unknown species submitted for expert review.");
    } catch {
      setUnknownReview("ready");
      toast.error("Could not submit for expert review. Please try again.");
    }
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (unknownReview || aiStatus === "identifying") return;
    if (gpsLoading) {
      toast.info("Wait for the GPS lookup to finish.");
      return;
    }
    if (gpsLookup && Number(form.lat) === gpsLookup.lat && Number(form.lng) === gpsLookup.lng) {
      if (gpsLookup.status === "outside_panabo") {
        toast.error("This location is outside the Panabo City inventory area.");
        return;
      }
      if (gpsLookup.status === "uncertain") {
        toast.warning("Barangay uncertain. Please capture GPS again.");
        return;
      }
    }

    const dbhUpdate = getMeasurementUpdate("dbh_cm", "DBH measurement");
    const heightUpdate = getMeasurementUpdate("height_m", "height measurement");
    const nextMeasurementErrors = {
      dbh_cm: dbhUpdate.error,
      height_m: heightUpdate.error,
    };
    setMeasurementErrors(nextMeasurementErrors);

    if (dbhUpdate.error || heightUpdate.error) return;

    // Upload photo to Supabase if a new file was selected
    let finalPhotoUrl = form.photo_url;
    let pendingPhotoFile = null;
    if (photoFile && !form.photo_url) {
      if (!navigator.onLine) {
        // G7: offline - the photo stays with the record and uploads during
        // sync. It is never dropped silently.
        pendingPhotoFile = photoFile;
        toast.info("Offline - your photo is saved with this record and uploads during sync.");
      } else {
        setPhotoLoading(true);
        try {
          const { file_url } = await storageApi.uploadPhoto(
            photoFile,
            photoUploadPurpose,
          );
          finalPhotoUrl = file_url;
          // Cache the uploaded URL so a retry of the same form does not
          // upload the same photo again.
          set("photo_url", file_url);
        } catch (error) {
          if (!error?.response) {
            // Connection dropped mid-upload: keep the photo attached and let
            // the caller decide (offline queue / explicit retry).
            pendingPhotoFile = photoFile;
            toast.warning(
              "Connection lost during photo upload. The photo stays with this record.",
            );
          } else {
            // Server rejected the upload outright - explicit, never silent.
            toast.error("Photo upload failed. Saving without photo.");
          }
        } finally {
          setPhotoLoading(false);
        }
      }
    }

    const toCoordinate = (value) => {
      const trimmed = typeof value === "string" ? value.trim() : value;
      if (trimmed === "" || trimmed === null || trimmed === undefined) return undefined;
      const parsed = Number(trimmed);
      return Number.isFinite(parsed) ? parsed : NaN;
    };
    const lat = toCoordinate(form.lat);
    const lng = toCoordinate(form.lng);
    const latInvalid = lat !== undefined && (Number.isNaN(lat) || lat < -90 || lat > 90);
    const lngInvalid = lng !== undefined && (Number.isNaN(lng) || lng < -180 || lng > 180);
    if (latInvalid || lngInvalid) {
      toast.error(
        "Invalid GPS coordinates. Latitude must be between -90 and 90, longitude between -180 and 180. Leave a field empty if that coordinate is unavailable."
      );
      return;
    }

    const payload = { ...form };
    const estimatedDimensions = ["dbh_cm", "height_m"].filter((key) => {
      const value = Number(form[key]);
      return value > 0 && (
        value === aiFilled.current[key] ||
        (savedEstimate.dimensions.includes(key) && value === Number(initial[key]))
      );
    });
    payload.notes = appendMeasurementNote(form.notes, estimatedDimensions);
    delete payload.dbh_cm;
    delete payload.height_m;
    delete payload.biomass_kg;
    delete payload.carbon_kg;

    Object.assign(payload, {
      photo_url: finalPhotoUrl || undefined,
      lat,
      lng,
    });

    if (dbhUpdate.value !== undefined) payload.dbh_cm = dbhUpdate.value;
    if (heightUpdate.value !== undefined) payload.height_m = heightUpdate.value;

    // G7: hand the raw photo file to the caller so offline saves can store it
    // as a durable Blob instead of losing it.
    onSubmit(payload, { photoFile: pendingPhotoFile });
  };

  const isAiLoading = aiStatus === "identifying" || aiStatus === "estimating";

  const locationFields = (
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
          aria-label="Latitude" placeholder="Latitude"
          value={form.lat}
          onChange={(e) => set("lat", e.target.value)}
          type="number"
          step="any"
        />
        <Input
          aria-label="Longitude" placeholder="Longitude"
          value={form.lng}
          onChange={(e) => set("lng", e.target.value)}
          type="number"
          step="any"
        />
      </div>
      <Input
        aria-label="Barangay" placeholder="Barangay"
        value={form.barangay}
        onChange={(e) => set("barangay", e.target.value)}
      />
      {!unknownDialogOpen && (
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
      )}
    </div>
  );

  return (
    <form
      onSubmit={handleSubmit}
      className={editLayout ? "grid gap-4 lg:grid-cols-2" : "flex flex-col gap-6"}
    >

      <div className={editLayout ? "grid min-w-0 items-start gap-4 rounded-xl border border-border bg-card p-4 sm:p-5 lg:col-span-2 lg:grid-cols-[minmax(0,2fr)_minmax(0,3fr)]" : "contents"}>
        {/* ── Tree Photo ── */}
        <div className="space-y-2">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <Label>Tree Photo</Label>
            {(!editLayout || photoFile) && <div className="flex flex-wrap gap-2">
              {comparisonEnabled && (
                <Button
                  type="button"
                  size="sm"
                  variant="outline"
                  onClick={handleCompareModels}
                  disabled={!photoFile || isAiLoading || comparison?.loading}
                >
                  {comparison?.loading ? "Comparing models…" : "Compare Models"}
                </Button>
              )}
              <Button
                type="button"
                size="sm"
                variant="outline"
                onClick={() => handleAIIdentify()}
                disabled={!photoFile || isAiLoading || comparison?.loading || unknownReview === "submitting" || unknownReview === "submitted"}
                className="flex items-center gap-1.5 text-xs border-primary/30 text-primary hover:bg-primary/5"
              >
                <Sparkles className="w-3.5 h-3.5" />
                AI species identification
              </Button>
            </div>}
          </div>

          <div className="flex flex-wrap items-start gap-3">
            {/* Photo preview */}
            {photoPreview ? (
              <div className={`relative shrink-0 ${editLayout ? "h-40 w-40" : "h-32 w-32"}`}>
                <TreePhotoPreview
                  src={photoPreview}
                  alt="Tree preview"
                  className="h-full w-full overflow-hidden rounded-lg border border-border"
                  thumbnailClassName="h-full w-full object-cover"
                />
                <button
                  type="button"
                  aria-label="Remove tree photo"
                    disabled={unknownReview === "submitting"}
                  onClick={removePhoto}
                  className="absolute right-1 top-1 flex h-7 w-7 items-center justify-center rounded-full bg-black/70"
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
                  aria-label="Tree photo"
                  disabled={unknownReview === "submitting"}
                  accept="image/jpeg,image/png,image/webp"
                  className="hidden"
                  onChange={handlePhotoSelect}
                />
              </label>
            </div>
          </div>

          {/* Preliminary AI suggestion (EfficientNet-B0) */}
          {false && roboflowCandidate && (
            <div className="rounded-xl border border-sky-200 bg-sky-50/70 p-4 space-y-2">
              <p className="text-sm font-semibold text-sky-900">
                Preliminary AI suggestion
              </p>
              <div className="flex flex-wrap items-center justify-between gap-2">
                <p className="font-medium text-foreground">
                  {roboflowCandidate.common_name || "Unknown"}
                </p>
                {Number.isFinite(Number(roboflowCandidate.confidence_percent)) && (
                  <span className="text-sm font-medium text-sky-900">
                    {Number(roboflowCandidate.confidence_percent).toFixed(2)}% score
                  </span>
                )}
              </div>
              <p className="text-xs text-muted-foreground">
                EfficientNet-B0 ? {roboflowCandidate.supported_classes || 16} supported classes
              </p>
              <p className="text-xs text-sky-900">
                This is an unverified AI prediction. Its score is not a calibrated
                probability of correctness. Verify the species independently before
                entering it into an official tree record.
              </p>
            </div>
          )}

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
              <p>
                {speciesPrediction?.name ? `Identified as ${speciesPrediction.name}.` : "Species suggestion filled."}
                {speciesPrediction?.confidence && <> <strong>Confidence {speciesPrediction.confidence}.</strong></>}
                {" Review before saving."}
              </p>
            </div>
          )}
          {comparison?.error && <p role="alert" className="text-sm text-destructive">{comparison.error}</p>}
          {comparison?.results && (
            <div className="overflow-x-auto rounded-lg border border-border">
              <table className="w-full text-left text-sm">
                <caption className="px-3 py-2 text-left font-medium">Species predictions for this photo</caption>
                <thead className="bg-muted/50 text-xs text-muted-foreground">
                  <tr>
                    <th scope="col" className="px-3 py-2">Model</th>
                    <th scope="col" className="px-3 py-2">Top prediction</th>
                    <th scope="col" className="px-3 py-2 text-right">Score</th>
                  </tr>
                </thead>
                <tbody>
                  {comparison.results.map((row) => (
                    <tr key={row.model_name} className="border-t border-border">
                      <th scope="row" className="px-3 py-2 font-medium">
                        {row.model_name}
                        {row.model_name === comparison.selected_model && (
                          <span className="ml-2 text-xs font-normal text-primary">Selected</span>
                        )}
                      </th>
                      <td className="px-3 py-2">{row.top_label ?? row.error}</td>
                      <td className="px-3 py-2 text-right tabular-nums">
                        {row.score_percent != null ? `${row.score_percent}%` : "—"}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>

        {/* ── Species ── */}

        <div className={editLayout ? "min-w-0 space-y-4" : "contents"}>
          {/* ── Endangered Warning ── */}
          {endangeredInfo && (
            <div className={`p-4 rounded-xl border-2 flex items-start gap-3 ${endangeredInfo.code === "CR" ? "border-red-400 bg-red-50" :
              endangeredInfo.code === "EN" ? "border-orange-400 bg-orange-50" :
                "border-yellow-400 bg-yellow-50"
              }`}>
              <span className="text-2xl flex-shrink-0">
                {endangeredInfo.code === "CR" ? "⛔" :
                  endangeredInfo.code === "EN" ? "🚫" : "⚠️"}
              </span>
              <div>
                <p className={`font-bold text-sm ${endangeredInfo.code === "CR" ? "text-red-700" :
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
        </div>
      </div>

      <div className={editLayout ? "min-w-0 space-y-4 rounded-xl border border-border bg-card p-4 sm:p-5" : "contents"}>
        {editLayout && <h3 className="font-fraunces text-lg font-semibold">Measurements</h3>}
        {/* ── Measurements ── */}
        {photoFile && localPhotoUrl && <GalleryTreePredictions key={photoPreview} file={photoFile}
          scientificName={unknownDialogOpen ? unknownCandidate?.scientific_name : identifiedSpecies ? form.scientific_name : ''}
          preliminarySpecies={unknownDialogOpen}
          portalTarget={unknownDialogOpen ? unknownAnalysisSlot : null}
          onDimensions={fillDimensions}
          onAnalysisPending={setPhotoAnalysisPending}
          ageDbhCm={Number(form.dbh_cm) > 0 ? Number(form.dbh_cm) : null}
          ageHeightM={Number(form.height_m) > 0 ? Number(form.height_m) : null}
          dimensionsSource={Object.keys(aiFilled.current).length ? 'ai_prediction' : 'measurement'} />}
        {Object.keys(aiFilled.current).length > 0 && <p className="text-sm text-muted-foreground">
          AI-estimated DBH/height filled below. Review or correct before saving; these are not field-validated measurements.
        </p>}
        {!editLayout && form.dbh_cm && (
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
              aria-invalid={Boolean(measurementErrors.dbh_cm)}
              aria-describedby={measurementErrors.dbh_cm ? "dbh_cm_error" : undefined}
            />
            {measurementErrors.dbh_cm && (
              <p id="dbh_cm_error" className="text-sm text-destructive" role="alert">
                {measurementErrors.dbh_cm}
              </p>
            )}
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
              aria-invalid={Boolean(measurementErrors.height_m)}
              aria-describedby={measurementErrors.height_m ? "height_m_error" : undefined}
            />
            {measurementErrors.height_m && (
              <p id="height_m_error" className="text-sm text-destructive" role="alert">
                {measurementErrors.height_m}
              </p>
            )}
            <TreeHeightCalculator
              onAccept={(height) => set("height_m", height.toFixed(2))}
            />
          </div>
        </div>

        {/* Carbon preview */}
        {computed.biomass && (
          <div className="p-3 bg-primary/5 border border-primary/20 rounded-lg flex flex-wrap gap-x-6 gap-y-2 text-sm">
            <div>
              <span className="text-muted-foreground">Biomass: </span>
              <span className="font-semibold text-primary">{computed.biomass} kg</span>
            </div>
            <div>
              <span className="text-muted-foreground">{Object.keys(aiFilled.current).length ? 'Approximate carbon (AI-estimated sizes): ' : 'Carbon Stock: '}</span>
              <span className="font-semibold text-primary">{computed.carbon} kg</span>
            </div>
          </div>
        )}
      </div>

      <div className={editLayout ? "min-w-0 space-y-4 rounded-xl border border-border bg-card p-4 sm:p-5" : "contents"}>
        {editLayout && <h3 className="font-fraunces text-lg font-semibold">Record and location</h3>}
        {/* ── Health & Date ── */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div className="space-y-2">
            <Label>Health Status *</Label>
            <Select value={form.health_status} onValueChange={(v) => set("health_status", v)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="Not assessed">Not assessed</SelectItem>
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
        {!unknownDialogOpen && locationFields}
      </div>

      <div className={editLayout ? "min-w-0 rounded-xl border border-border bg-card p-4 sm:p-5 lg:col-span-2" : "contents"}>
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
      </div>

      <Button
        type={unknownReview ? "button" : "submit"}
        onClick={unknownReview ? () => setUnknownDialogOpen(true) : undefined}
        disabled={loading || photoLoading || isAiLoading || unknownReview === "submitting" || unknownReview === "submitted"}
        className={editLayout ? "justify-self-end lg:col-span-2" : compactSubmit ? "self-end gap-2" : "w-full flex items-center gap-2"}
      >
        {(loading || photoLoading) && <Loader2 className="w-4 h-4 animate-spin" />}
        {unknownReview === "submitted" ? "Submitted for expert review"
          : unknownReview === "submitting" ? "Submitting for review..."
          : unknownReview ? "Submit Unknown Species"
          : photoLoading ? "Uploading photo..."
          : loading ? savingLabel : submitLabel}
      </Button>
      <Dialog
        open={unknownDialogOpen}
        onOpenChange={(open) => {
          if (unknownReview !== "submitting") setUnknownDialogOpen(open);
        }}
      >
        <DialogContent className="max-h-[90dvh] w-[calc(100%_-_2rem)] max-w-2xl overflow-y-auto rounded-xl">
          <DialogTitle className="pr-8">Species needs expert review</DialogTitle>
          <DialogDescription>
            The AI score is below 75%. Review the photo, suggested species, and measurements before submitting.
          </DialogDescription>
          <div className="grid items-start gap-4 sm:grid-cols-2">
            {photoPreview && (
              <div className="space-y-2">
                <p className="text-sm font-medium">Tree photo</p>
                <TreePhotoPreview
                  src={photoPreview}
                  alt="Tree photo for expert review"
                  className="w-full overflow-hidden rounded-lg border border-border bg-muted"
                  thumbnailClassName="h-52 w-full object-contain"
                />
              </div>
            )}
            <div className="space-y-3">
              <div className="space-y-1">
                <Label htmlFor="review-common-name">Suggested common name</Label>
                <Input id="review-common-name" value={unknownCandidate?.common_name || "Unavailable"} readOnly />
              </div>
              <div className="space-y-1">
                <Label htmlFor="review-scientific-name">Suggested scientific name</Label>
                <Input id="review-scientific-name" value={unknownCandidate?.scientific_name || "Unavailable"} readOnly />
              </div>
              <div className="space-y-1">
                <Label htmlFor="review-confidence">AI confidence</Label>
                <Input
                  id="review-confidence"
                  value={Number.isFinite(unknownCandidate?.confidence_percent)
                    ? `${unknownCandidate.confidence_percent}%`
                    : "Unavailable"}
                  readOnly
                />
              </div>
            </div>
          </div>
          <div ref={setUnknownAnalysisSlot} />
          <dl className="grid grid-cols-3 gap-2 rounded-lg border bg-muted/30 p-3 text-sm">
            {[
              ["DBH", Number(form.dbh_cm) > 0 ? `${Number(form.dbh_cm)} cm` : null],
              ["Height", Number(form.height_m) > 0 ? `${Number(form.height_m)} m` : null],
              ["Carbon stock", computed.carbon != null ? `${computed.carbon} kg` : null],
            ].map(([label, value]) => (
              <div key={label}>
                <dt className="text-muted-foreground">{label}</dt>
                <dd className="font-medium">{value ?? (photoAnalysisPending ? "Analyzing…" : "Unavailable")}</dd>
              </div>
            ))}
          </dl>
          {unknownDialogOpen && locationFields}
          <div className="flex flex-wrap justify-end gap-2">
            <Button
              type="button"
              variant="ghost"
              disabled={unknownReview === "submitting"}
              onClick={() => setUnknownDialogOpen(false)}
            >
              Back to measurements
            </Button>
            <Button
              type="button"
              disabled={unknownReview !== "ready" || photoAnalysisPending || gpsLoading}
              onClick={submitUnknownPhoto}
            >
              {unknownReview === "submitting" ? "Submitting for review..." : "Submit Unknown Species"}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </form>
  );
}
