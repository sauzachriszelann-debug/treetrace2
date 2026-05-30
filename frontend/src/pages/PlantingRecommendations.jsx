import { useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useSearchParams } from "react-router-dom";
import { toast } from "sonner";
import { plantingApi } from "@/api/planting";
import { storageApi } from "@/api/storage";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Check, ImageIcon, Loader2, Plus, Search, X } from "lucide-react";

export default function PlantingRecommendations() {
  const qc = useQueryClient();
  const [params] = useSearchParams();
  const focusReview = params.get("review") === "pending";
  const [barangay, setBarangay] = useState("");
  const [draft, setDraft] = useState({});
  const [photo, setPhoto] = useState(null);
  const [saving, setSaving] = useState(false);
  const [rejecting, setRejecting] = useState(null);
  const [gallery, setGallery] = useState(null);

  const { data: suggestionsData = { suggestions: [] } } = useQuery({
    queryKey: ["planting-suggestions", barangay],
    queryFn: () => plantingApi.suggestions({ barangay }),
  });
  const { data: records = [] } = useQuery({
    queryKey: ["planting-records", barangay],
    queryFn: () => plantingApi.list({ barangay }),
  });

  const pending = records.filter((item) => item.status === "pending");
  const reviewed = records.filter((item) => item.status !== "pending");

  const suggestions = useMemo(() => suggestionsData.suggestions || [], [suggestionsData]);

  const saveRecommendation = async (seed = null) => {
    const source = seed || draft;
    if (!source.species_name?.trim()) {
      toast.error("Add the tree name first.");
      return;
    }
    setSaving(true);
    try {
      let photo_url = source.photo_url || "";
      if (photo) {
        const uploaded = await storageApi.uploadPhoto(photo);
        photo_url = uploaded.file_url;
      }
      await plantingApi.create({
        species_name: source.species_name,
        scientific_name: source.scientific_name || null,
        barangay: source.barangay || source.recommended_area || barangay || null,
        reason: source.reason || source.area_reason || null,
        photo_url: photo_url || null,
        status: "recommended",
        planted: false,
      });
      setDraft({});
      setPhoto(null);
      qc.invalidateQueries({ queryKey: ["planting-records"] });
      qc.invalidateQueries({ queryKey: ["planting-suggestions"] });
      toast.success("Planting recommendation saved.");
    } catch (err) {
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

  return (
    <div className="p-4 sm:p-6 lg:p-8">
      <div className="mb-6 flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <h1 className="font-fraunces text-2xl font-semibold sm:text-3xl">Planting Recommendations</h1>
          <p className="mt-1 text-muted-foreground">Review citizen plant requests and manage official planting suggestions.</p>
        </div>
        <div className="flex gap-2">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <Input className="pl-9" placeholder="Focus barangay" value={barangay} onChange={(e) => setBarangay(e.target.value)} />
          </div>
        </div>
      </div>

      {(focusReview || pending.length > 0) && (
        <section className="mb-8">
          <h2 className="mb-3 text-lg font-semibold">Citizen Suggestions for Review</h2>
          {pending.length === 0 ? (
            <Card><CardContent className="p-6 text-muted-foreground">No suggested plants waiting for review.</CardContent></Card>
          ) : (
            <div className="grid gap-4 lg:grid-cols-2">
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
          <Card className="mb-8">
            <CardHeader><CardTitle className="font-fraunces">Add Official Recommendation</CardTitle></CardHeader>
            <CardContent className="grid gap-3 md:grid-cols-2">
              <Input placeholder="Tree to plant" value={draft.species_name || ""} onChange={(e) => setDraft({ ...draft, species_name: e.target.value })} />
              <Input placeholder="Scientific name" value={draft.scientific_name || ""} onChange={(e) => setDraft({ ...draft, scientific_name: e.target.value })} />
              <Input placeholder="Barangay / area" value={draft.barangay || ""} onChange={(e) => setDraft({ ...draft, barangay: e.target.value })} />
              <Input type="file" accept="image/*" onChange={(e) => setPhoto(e.target.files?.[0] || null)} />
              <Textarea className="md:col-span-2" placeholder="Why needed in this area?" value={draft.reason || ""} onChange={(e) => setDraft({ ...draft, reason: e.target.value })} />
              <Button className="md:col-span-2" onClick={() => saveRecommendation()} disabled={saving}>
                {saving ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Plus className="mr-2 h-4 w-4" />}
                Save Recommendation
              </Button>
            </CardContent>
          </Card>

          <section className="mb-8">
            <h2 className="mb-3 text-lg font-semibold">Suggested Trees to Plant</h2>
            <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
              {suggestions.map((item) => (
                <SuggestionCard key={`${item.species_name}-${item.recommended_area}`} item={item} onAdd={() => saveRecommendation(item)} onGallery={setGallery} />
              ))}
            </div>
          </section>
        </>
      )}

      <section>
        <h2 className="mb-3 text-lg font-semibold">Planting Records</h2>
        <div className="grid gap-4 lg:grid-cols-2">
          {reviewed.map((item) => <PlantingRecord key={item.id} item={item} onGallery={setGallery} />)}
        </div>
      </section>

      <PhotoGallery gallery={gallery} onClose={() => setGallery(null)} />
    </div>
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
    <Card className="overflow-hidden">
      <button type="button" className="h-40 w-full bg-muted" onClick={() => onGallery({ title: item.species_name, description: item.reason, images })}>
        {images[0] ? <img src={images[0]} alt={item.species_name} className="h-full w-full object-cover" /> : <ImageIcon className="mx-auto mt-12 h-8 w-8 text-muted-foreground" />}
      </button>
      <CardContent className="space-y-2 p-4">
        <div className="flex items-start justify-between gap-2">
          <div>
            <h3 className="font-semibold">{item.species_name}</h3>
            <p className="text-xs italic text-muted-foreground">{item.scientific_name}</p>
          </div>
          <Badge variant="outline">{item.priority}</Badge>
        </div>
        <p className="text-xs font-medium text-primary">{item.recommended_area}</p>
        <p className="line-clamp-3 text-sm text-muted-foreground">{item.area_reason || item.reason}</p>
        <Button className="w-full" variant="outline" onClick={onAdd}>Add Plant</Button>
      </CardContent>
    </Card>
  );
}

function PlantingRecord({ item, children, onGallery }) {
  const images = imagesFor(item);
  return (
    <Card>
      <CardContent className="p-4">
        <div className="flex gap-3">
          <button type="button" onClick={() => onGallery({ title: item.species_name, description: item.reason, images })} className="h-20 w-24 shrink-0 overflow-hidden rounded-lg bg-muted">
            {images[0] ? <img src={images[0]} alt={item.species_name} className="h-full w-full object-cover" /> : <ImageIcon className="mx-auto mt-6 h-7 w-7 text-muted-foreground" />}
          </button>
          <div className="min-w-0 flex-1">
            <div className="flex items-start justify-between gap-2">
              <div>
                <h3 className="font-semibold">{item.species_name}</h3>
                <p className="text-xs italic text-muted-foreground">{item.scientific_name}</p>
              </div>
              <Badge>{item.status}</Badge>
            </div>
            <p className="text-sm text-primary">{item.barangay || "No area selected"}</p>
            <p className="mt-2 line-clamp-3 text-sm text-muted-foreground">{item.reason || "No reason added."}</p>
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
      <DialogContent className="max-w-2xl">
        <DialogHeader><DialogTitle>{gallery.title}</DialogTitle></DialogHeader>
        <div className="overflow-hidden rounded-xl bg-muted">
          {images[index] && <img src={images[index]} alt={gallery.title} className="h-[360px] w-full object-cover" />}
        </div>
        {images.length > 1 && (
          <div className="flex justify-between">
            <Button variant="outline" onClick={() => setIndex((index - 1 + images.length) % images.length)}>Previous</Button>
            <Button variant="outline" onClick={() => setIndex((index + 1) % images.length)}>Next</Button>
          </div>
        )}
        <p className="text-sm text-muted-foreground">{gallery.description}</p>
      </DialogContent>
    </Dialog>
  );
}
