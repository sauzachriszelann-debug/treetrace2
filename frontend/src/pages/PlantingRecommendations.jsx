import { useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useSearchParams } from "react-router-dom";
import { toast } from "sonner";
import { plantingApi } from "@/api/planting";
import { storageApi } from "@/api/storage";
import { useOfflineSyncStore } from "@/offline/OfflineSyncProvider";
import { useAuth } from "@/lib/AuthContext";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { ArrowLeft, Check, ImageIcon, Loader2, Plus, Search, X } from "lucide-react";

export default function PlantingRecommendations() {
  const qc = useQueryClient();
  const { user } = useAuth();
  const { enqueue } = useOfflineSyncStore();
  const [params] = useSearchParams();
  const focusReview = params.get("review") === "pending";
  const [barangay, setBarangay] = useState("");
  const [draft, setDraft] = useState({});
  const [photo, setPhoto] = useState(null);
  const [saving, setSaving] = useState(false);
  const [rejecting, setRejecting] = useState(null);
  const [gallery, setGallery] = useState(null);
  const [speciesPhotoDraft, setSpeciesPhotoDraft] = useState({});
  const [speciesPhotoFile, setSpeciesPhotoFile] = useState(null);
  const [savingSpeciesPhoto, setSavingSpeciesPhoto] = useState(false);
  const canManageSpeciesPhotos = user?.role === "admin";

  const { data: suggestionsData = { suggestions: [] } } = useQuery({
    queryKey: ["planting-suggestions", barangay],
    queryFn: () => plantingApi.suggestions({ barangay }),
  });
  const { data: records = [] } = useQuery({
    queryKey: ["planting-records", barangay],
    queryFn: () => plantingApi.list({ barangay }),
  });
  const { data: speciesPhotos = [] } = useQuery({
    queryKey: ["planting-species-photos"],
    queryFn: () => plantingApi.speciesPhotos(),
    enabled: canManageSpeciesPhotos,
  });

  const pending = records.filter((item) => item.status === "pending");
  const reviewed = records.filter((item) => item.status !== "pending");

  const suggestions = useMemo(() => suggestionsData.suggestions || [], [suggestionsData]);

  const backToBarangayGaps = () => {
    setBarangay("");
    qc.invalidateQueries({ queryKey: ["planting-suggestions"] });
    qc.invalidateQueries({ queryKey: ["planting-records"] });
  };

  const saveRecommendation = async (seed = null) => {
    const source = seed || draft;
    if (!source.species_name?.trim()) {
      toast.error("Add the tree name first.");
      return;
    }
    setSaving(true);
    let photo_url = source.photo_url || "";
    let photoBlob = null;
    let payload = null;
    try {
      if (photo) {
        if (!navigator.onLine) {
          // G7: keep the photo with the record; it uploads during sync.
          photoBlob = photo;
        } else {
          try {
            const uploaded = await storageApi.uploadPhoto(photo, "planting_submission");
            photo_url = uploaded.file_url;
          } catch (error) {
            if (!error?.response) {
              // Connection dropped mid-upload: keep the photo attached.
              photoBlob = photo;
            } else {
              throw error; // server rejection: existing explicit error path
            }
          }
        }
      }
      payload = {
        species_name: source.species_name,
        scientific_name: source.scientific_name || null,
        barangay: source.barangay || source.recommended_area || barangay || null,
        reason: source.reason || source.area_reason || null,
        photo_url: photo_url || null,
        status: "recommended",
        planted: false,
      };
      if (!navigator.onLine || photoBlob) {
        // Fully offline (or the photo upload never completed): nothing was
        // created server-side, so the queue may replay this after review.
        await enqueue("CREATE_PLANTING_RECOMMENDATION", payload, { photoBlob });
        setDraft({});
        setPhoto(null);
        toast.success(
          "Saved offline. Review it in Field Sync - only verified records upload.",
        );
        return;
      }
      await plantingApi.create(payload);
      setDraft({});
      setPhoto(null);
      qc.invalidateQueries({ queryKey: ["planting-records"] });
      qc.invalidateQueries({ queryKey: ["planting-suggestions"] });
      toast.success("Planting recommendation saved.");
    } catch (err) {
      if (!err?.response && payload) {
        // Uncertain outcome, no idempotency key (G7 req 6): hold for review,
        // never auto-retry.
        try {
          await enqueue("CREATE_PLANTING_RECOMMENDATION", payload, {
            requiresReview: true,
            reviewReason:
              "This save failed after the request may have reached the server. " +
              "It is kept for review and will not be retried automatically, " +
              "because a blind retry could create a duplicate planting recommendation.",
          });
          setDraft({});
          setPhoto(null);
          toast.warning(
            "Connection dropped - the recommendation may have reached the server. Saved for review in Field Sync; it will not be retried automatically.",
          );
          return;
        } catch {
          /* fall through to the generic error below */
        }
      }
      toast.error(err?.response?.data?.detail || "Could not save recommendation.");
    } finally {
      setSaving(false);
    }
  };

  const review = async (item, approved) => {
    const note = rejecting?.id === item.id ? rejecting.reason.trim() : "";
    if (!approved && !note) {
      toast.error("Add a rejection reason first.");
      return;
    }
    const reason = [
      item.reason,
      `${approved ? "Approved" : "Rejected"} by admin/field: ${
        note || "Suitable for planting."
      }`,
    ].filter(Boolean).join("\n\n");
    await plantingApi.update(item.id, {
      status: approved ? "approved" : "rejected",
      reason,
    });
    setRejecting(null);
    qc.invalidateQueries({ queryKey: ["planting-records"] });
    qc.invalidateQueries({ queryKey: ["planting-suggestions"] });
    toast.success(approved ? "Suggestion approved." : "Suggestion rejected.");
  };

  const saveSpeciesPhoto = async () => {
    if (!speciesPhotoDraft.species_name?.trim() ||
        !speciesPhotoDraft.scientific_name?.trim() || !speciesPhotoFile) {
      toast.error("Enter both tree names and choose a verified photo.");
      return;
    }
    setSavingSpeciesPhoto(true);
    try {
      const uploaded = await storageApi.uploadPhoto(speciesPhotoFile, "planting_submission");
      await plantingApi.saveSpeciesPhoto({
        ...speciesPhotoDraft,
        photo_url: uploaded.file_url,
      });
      setSpeciesPhotoDraft({});
      setSpeciesPhotoFile(null);
      qc.invalidateQueries({ queryKey: ["planting-species-photos"] });
      qc.invalidateQueries({ queryKey: ["planting-suggestions"] });
      toast.success("Verified species photo saved and linked to recommendations.");
    } catch (err) {
      toast.error(err?.response?.data?.detail || "Could not save the species photo.");
    } finally {
      setSavingSpeciesPhoto(false);
    }
  };

  return (
    <main className="mx-auto w-full max-w-6xl min-w-0 p-3 sm:p-6 lg:p-8">
      <div className="mb-6 flex min-w-0 flex-col gap-4 sm:gap-5 lg:flex-row lg:items-end lg:justify-between">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2 sm:gap-3">
            {barangay.trim() && (
              <Button
                type="button"
                className="h-8 w-auto shrink-0 gap-1.5 whitespace-nowrap px-2.5 text-xs"
                variant="outline"
                size="sm"
                onClick={backToBarangayGaps}
              >
                <ArrowLeft className="h-3.5 w-3.5" />
                Back
              </Button>
            )}
            <h1 className="font-fraunces text-2xl font-semibold sm:text-3xl">Planting Recommendations</h1>
          </div>
          <p className="mt-1 max-w-2xl text-sm text-muted-foreground sm:text-base">Review citizen plant requests and manage official planting suggestions.</p>
        </div>
        <div className="relative w-full sm:max-w-sm lg:w-64 lg:shrink-0">
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <Input className="pl-9" placeholder="Focus barangay" value={barangay} onChange={(e) => setBarangay(e.target.value)} />
        </div>
      </div>

      {!focusReview && !barangay.trim() && suggestionsData.barangay_needs?.length > 0 && (
        <Card className="mb-6 min-w-0">
          <CardHeader className="p-4 pb-3 sm:p-6 sm:pb-3">
            <CardTitle className="text-base leading-snug sm:text-lg">Barangays with the largest recorded species gaps</CardTitle>
            <p className="text-sm leading-relaxed text-muted-foreground">
              Counts priority species with zero or one record. Based on TreeTrace inventory only; fewer records do not prove a planting site is needed. Barangays without tree records cannot be ranked yet.
            </p>
          </CardHeader>
          <CardContent className="grid min-w-0 grid-cols-1 gap-3 p-4 pt-0 sm:grid-cols-2 sm:p-6 sm:pt-0 xl:grid-cols-3">
            {suggestionsData.barangay_needs.slice(0, 6).map((area) => (
              <div key={area.barangay} className="min-w-0 rounded-lg border p-3 sm:p-4">
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <p className="break-words font-medium">{area.barangay}</p>
                    <p className="text-xs text-muted-foreground">
                      {area.recorded_tree_count} recorded trees · {area.recorded_species_count} recorded species
                    </p>
                  </div>
                  <Badge variant="outline">{area.inventory_gap_count} gaps</Badge>
                </div>
                <p className="mt-2 break-words text-xs leading-relaxed text-muted-foreground">
                  Priority species with 0–1 records: {area.underrepresented_native_priority_species.map((item) => `${item.species_name} (${item.recorded_count})`).join(", ") || "None"}
                </p>
                {area.missing_verified_photo_count > 0 && (
                  <p className="mt-1 text-xs text-amber-700">
                    {area.missing_verified_photo_count} suggested species need verified photos
                  </p>
                )}
                <Button className="mt-3 h-auto min-h-9 w-full whitespace-normal py-2 leading-snug" size="sm" variant="outline" onClick={() => setBarangay(area.barangay)}>
                  Show recommendations for {area.barangay}
                </Button>
              </div>
            ))}
          </CardContent>
        </Card>
      )}

      {(focusReview || pending.length > 0) && (
        <section className="mb-8">
          <h2 className="mb-3 text-lg font-semibold">Citizen Suggestions for Review</h2>
          {pending.length === 0 ? (
            <Card><CardContent className="p-6 text-muted-foreground">No suggested plants waiting for review.</CardContent></Card>
          ) : (
            <div className="grid min-w-0 grid-cols-1 gap-4 xl:grid-cols-2">
              {pending.map((item) => (
                <PlantingRecord key={item.id} item={item} onGallery={setGallery}>
                  {rejecting?.id === item.id && (
                    <Textarea
                      className="mt-3"
                      placeholder="Reason for rejection"
                      value={rejecting.reason}
                      onChange={(e) => setRejecting({ id: item.id, reason: e.target.value })}
                    />
                  )}
                  <div className="mt-3 flex flex-wrap gap-2">
                    <Button variant="outline" onClick={() => setRejecting({ id: item.id, reason: "" })}>
                      <X className="mr-2 h-4 w-4" /> Reject
                    </Button>
                    {rejecting?.id === item.id && <Button variant="destructive" onClick={() => review(item, false)}>Confirm Reject</Button>}
                    <Button onClick={() => review(item, true)}><Check className="mr-2 h-4 w-4" /> Approve</Button>
                  </div>
                </PlantingRecord>
              ))}
            </div>
          )}
        </section>
      )}

      {!focusReview && (
        <>
          {canManageSpeciesPhotos && (
            <Card className="mb-8">
              <CardHeader><CardTitle className="font-fraunces">Verified Species Photos</CardTitle></CardHeader>
              <CardContent className="space-y-3 p-4 sm:p-6">
                <p className="text-sm text-muted-foreground">Upload a photo you have checked. It will be reused whenever this species appears in planting suggestions.</p>
                <div className="grid min-w-0 grid-cols-1 gap-3 sm:grid-cols-2">
                  <Input placeholder="Common name, e.g. Narra" value={speciesPhotoDraft.species_name || ""} onChange={(e) => setSpeciesPhotoDraft({ ...speciesPhotoDraft, species_name: e.target.value })} />
                  <Input placeholder="Scientific name, e.g. Pterocarpus indicus" value={speciesPhotoDraft.scientific_name || ""} onChange={(e) => setSpeciesPhotoDraft({ ...speciesPhotoDraft, scientific_name: e.target.value })} />
                  <Input type="file" accept="image/*" onChange={(e) => setSpeciesPhotoFile(e.target.files?.[0] || null)} />
                  <Button className="w-fit justify-self-end px-4" onClick={saveSpeciesPhoto} disabled={savingSpeciesPhoto}>
                    {savingSpeciesPhoto ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <ImageIcon className="mr-2 h-4 w-4" />}
                    Save verified photo
                  </Button>
                </div>
                {speciesPhotos.length > 0 && (
                  <p className="text-xs text-muted-foreground">Saved species photos: {speciesPhotos.map((item) => item.species_name).join(", ")}</p>
                )}
              </CardContent>
            </Card>
          )}
          <Card className="mb-8">
            <CardHeader><CardTitle className="font-fraunces">Add Official Recommendation</CardTitle></CardHeader>
            <CardContent className="grid min-w-0 grid-cols-1 gap-3 p-4 sm:grid-cols-2 sm:p-6">
              <Input placeholder="Tree to plant" value={draft.species_name || ""} onChange={(e) => setDraft({ ...draft, species_name: e.target.value })} />
              <Input placeholder="Scientific name" value={draft.scientific_name || ""} onChange={(e) => setDraft({ ...draft, scientific_name: e.target.value })} />
              <Input placeholder="Barangay / area" value={draft.barangay || ""} onChange={(e) => setDraft({ ...draft, barangay: e.target.value })} />
              <Input type="file" accept="image/*" onChange={(e) => setPhoto(e.target.files?.[0] || null)} />
              <Textarea className="sm:col-span-2" placeholder="Why needed in this area?" value={draft.reason || ""} onChange={(e) => setDraft({ ...draft, reason: e.target.value })} />
              <Button className="min-h-10 w-fit justify-self-end whitespace-nowrap px-4 sm:col-span-2" onClick={() => saveRecommendation()} disabled={saving}>
                {saving ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Plus className="mr-2 h-4 w-4" />}
                Save Recommendation
              </Button>
            </CardContent>
          </Card>

          <section className="mb-8">
            <h2 className="mb-3 text-lg font-semibold">Suggested Trees to Plant</h2>
            {barangay.trim() && (
              <p className="mb-3 text-sm text-muted-foreground">
                These suggestions use TreeTrace records for {barangay}. High means no trees of that species are recorded; Medium means one is recorded. This does not confirm the species is absent or that a specific site is suitable.
              </p>
            )}
            {suggestionsData.weather_context ? (
              <Card className="mb-4">
                <CardContent className="p-4 sm:p-5">
                  <p className="font-medium">Estimated local weather context</p>
                  <p className="mt-1 text-sm text-muted-foreground">
                    {suggestionsData.weather_context.mean_temperature_c}°C average temperature · {suggestionsData.weather_context.mean_annual_rainfall_mm} mm average annual rainfall
                    ({suggestionsData.weather_context.period})
                  </p>
                  <p className="mt-1 text-xs text-muted-foreground">
                    Five-year historical estimate from <a className="underline" href="https://open-meteo.com/" target="_blank" rel="noreferrer">Open-Meteo</a>, calculated at the center of available tree GPS records. It is not a soil test. TreeTrace has not yet matched climate thresholds to each species.
                  </p>
                </CardContent>
              </Card>
            ) : barangay.trim() && suggestionsData.barangay_has_inventory ? (
              <p className="mb-4 text-sm text-muted-foreground">
                Weather context is unavailable for this barangay because there are no geolocated tree records or the weather service could not be reached.
              </p>
            ) : null}
            {barangay.trim() && !suggestionsData.barangay_has_inventory && (
              <p className="mb-4 rounded-lg border border-amber-500/30 bg-amber-500/10 p-3 text-sm text-amber-800">
                No tree inventory records match “{barangay}”. Check the barangay name or add tree records before using inventory-based recommendations.
              </p>
            )}
            <div className="grid min-w-0 grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
              {suggestions.map((item) => (
                <SuggestionCard key={`${item.species_name}-${item.recommended_area}`} item={item} onAdd={() => saveRecommendation(item)} onGallery={setGallery} />
              ))}
            </div>
          </section>
        </>
      )}

      <section>
        <h2 className="mb-3 text-lg font-semibold">Planting Records</h2>
        <div className="grid min-w-0 grid-cols-1 gap-4 xl:grid-cols-2">
          {reviewed.map((item) => <PlantingRecord key={item.id} item={item} onGallery={setGallery} />)}
        </div>
      </section>

      <PhotoGallery gallery={gallery} onClose={() => setGallery(null)} />
    </main>
  );
}

function imagesFor(item) {
  const base = item.photo_url ? [item.photo_url] : [];
  if (Array.isArray(item.image_urls)) return [...base, ...item.image_urls].filter(Boolean);
  const name = item.species_name || "tree seedling";
  return [...base, `https://tse1.mm.bing.net/th?q=${encodeURIComponent(`${name} tree seedling`)}`];
}

function SuggestionCard({ item, onAdd, onGallery }) {
  const images = imagesFor(item);
  return (
    <Card className="min-w-0 overflow-hidden">
      <button type="button" className="h-40 w-full bg-muted" onClick={() => onGallery({ title: item.species_name, description: item.reason, images })}>
        {images[0] ? <img src={images[0]} alt={item.species_name} className="h-full w-full object-cover" /> : <ImageIcon className="mx-auto mt-12 h-8 w-8 text-muted-foreground" />}
      </button>
      <CardContent className="min-w-0 space-y-2 p-3 sm:p-4">
        {item.photo_missing && <p className="text-xs text-amber-700">{images.length ? "This photo is not verified for the species." : "Verified species photo needed."}</p>}
        <div className="flex min-w-0 items-start justify-between gap-2">
          <div className="min-w-0">
            <h3 className="break-words font-semibold">{item.species_name}</h3>
            <p className="break-words text-xs italic text-muted-foreground">{item.scientific_name}</p>
          </div>
          <div className="flex max-w-[48%] shrink-0 flex-wrap justify-end gap-1">
            {item.photo_verified && <Badge variant="secondary">Verified photo</Badge>}
            {item.conservation_status && item.conservation_status !== "Not Listed" && (
              <Badge variant="destructive">{item.conservation_status}</Badge>
            )}
            <Badge variant="outline">{item.priority}</Badge>
          </div>
        </div>
        <p className="break-words text-xs font-medium text-primary">{item.recommended_area}</p>
        <p className="break-words text-sm leading-relaxed text-muted-foreground">{item.area_reason || item.reason}</p>
        <Button className="min-h-10 w-full" variant="outline" onClick={onAdd}>Add Plant</Button>
      </CardContent>
    </Card>
  );
}

function PlantingRecord({ item, children, onGallery }) {
  const images = imagesFor(item);
  return (
    <Card>
      <CardContent className="p-3 sm:p-4">
        <div className="flex gap-3">
          <button type="button" onClick={() => onGallery({ title: item.species_name, description: item.reason, images })} className="h-20 w-24 shrink-0 overflow-hidden rounded-lg bg-muted">
            {images[0] ? <img src={images[0]} alt={item.species_name} className="h-full w-full object-cover" /> : <ImageIcon className="mx-auto mt-6 h-7 w-7 text-muted-foreground" />}
          </button>
          <div className="min-w-0 flex-1">
            <div className="flex min-w-0 flex-wrap items-start justify-between gap-2">
              <div className="min-w-0">
                <h3 className="break-words font-semibold">{item.species_name}</h3>
                <p className="break-words text-xs italic text-muted-foreground">{item.scientific_name}</p>
              </div>
              <Badge>{item.status}</Badge>
            </div>
            <p className="break-words text-sm text-primary">{item.barangay || "No area selected"}</p>
            <p className="mt-2 break-words text-sm leading-relaxed text-muted-foreground">{item.reason || "No reason added."}</p>
          </div>
        </div>
        {children}
      </CardContent>
    </Card>
  );
}

function PhotoGallery({ gallery, onClose }) {
  const [index, setIndex] = useState(0);
  if (!gallery) return null;
  const images = gallery.images || [];
  return (
    <Dialog open={!!gallery} onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="max-h-[90dvh] w-[calc(100%-1rem)] max-w-2xl overflow-y-auto p-4 sm:w-[calc(100%-2rem)] sm:p-6">
        <DialogHeader><DialogTitle>{gallery.title}</DialogTitle></DialogHeader>
        <div className="overflow-hidden rounded-xl bg-muted">
          {images[index] && <img src={images[index]} alt={gallery.title} className="h-[min(55dvh,360px)] w-full object-cover sm:h-[360px]" />}
        </div>
        {images.length > 1 && (
          <div className="flex flex-wrap justify-between gap-2">
            <Button variant="outline" onClick={() => setIndex((index - 1 + images.length) % images.length)}>Previous</Button>
            <Button variant="outline" onClick={() => setIndex((index + 1) % images.length)}>Next</Button>
          </div>
        )}
        <p className="text-sm text-muted-foreground">{gallery.description}</p>
      </DialogContent>
    </Dialog>
  );
}
