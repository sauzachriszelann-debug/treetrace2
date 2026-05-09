import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { aiApi } from "@/api/ai";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { CheckCircle2, Leaf, Loader2 } from "lucide-react";
import { toast } from "sonner";

export default function UnknownSpeciesReview() {
  const qc = useQueryClient();
  const [editing, setEditing] = useState({});
  const [savingId, setSavingId] = useState(null);

  const { data: submissions = [], isLoading } = useQuery({
    queryKey: ["unknown-species"],
    queryFn: aiApi.listUnknown,
  });

  const updateDraft = (id, key, value) => {
    setEditing((current) => ({
      ...current,
      [id]: { ...(current[id] || {}), [key]: value },
    }));
  };

  const review = async (entry, reviewed) => {
    const draft = editing[entry.id] || {};
    setSavingId(entry.id);
    try {
      await aiApi.reviewUnknown(entry.id, {
        reviewed,
        identified_as: draft.identified_as ?? entry.identified_as ?? entry.possible_name ?? "",
        review_notes: draft.review_notes ?? entry.review_notes ?? "",
      });
      qc.invalidateQueries({ queryKey: ["unknown-species"] });
      toast.success(reviewed ? "Submission reviewed." : "Submission reopened.");
    } catch (err) {
      toast.error(err?.response?.data?.detail || "Failed to update review.");
    } finally {
      setSavingId(null);
    }
  };

  return (
    <div className="p-8 max-w-6xl mx-auto">
      <div className="mb-6">
        <h1 className="font-fraunces text-3xl font-semibold">Unknown Species Review</h1>
        <p className="text-muted-foreground mt-1">
          Review community-submitted tree photos and identify species for future database improvement.
        </p>
      </div>

      {isLoading ? (
        <div className="h-40 bg-muted rounded-xl animate-pulse" />
      ) : submissions.length === 0 ? (
        <Card>
          <CardContent className="p-10 text-center text-muted-foreground">
            <Leaf className="w-10 h-10 mx-auto mb-3 opacity-40" />
            No unknown species submissions yet.
          </CardContent>
        </Card>
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          {submissions.map((entry) => {
            const draft = editing[entry.id] || {};
            return (
              <Card key={entry.id}>
                <CardContent className="p-4 space-y-4">
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <div className="flex items-center gap-2">
                        <h2 className="font-semibold">Submission #{entry.id}</h2>
                        <Badge variant={entry.reviewed ? "default" : "outline"}>
                          {entry.reviewed ? "Reviewed" : "Pending"}
                        </Badge>
                      </div>
                      <p className="text-xs text-muted-foreground">
                        {entry.barangay || "Unknown barangay"} · {entry.location_description || "No location note"}
                      </p>
                    </div>
                    {entry.reviewed && <CheckCircle2 className="w-5 h-5 text-emerald-600" />}
                  </div>

                  {entry.photo_url ? (
                    <img
                      src={entry.photo_url}
                      alt="Unknown tree submission"
                      className="w-full h-52 object-cover rounded-xl border"
                    />
                  ) : (
                    <div className="h-52 rounded-xl bg-muted flex items-center justify-center text-muted-foreground">
                      No photo URL
                    </div>
                  )}

                  <div className="text-sm space-y-1">
                    <p><span className="font-medium">Possible name:</span> {entry.possible_name || "Not provided"}</p>
                    <p><span className="font-medium">Notes:</span> {entry.submitter_notes || "None"}</p>
                  </div>

                  <div className="space-y-2">
                    <Input
                      placeholder="Identified species name"
                      value={draft.identified_as ?? entry.identified_as ?? ""}
                      onChange={(e) => updateDraft(entry.id, "identified_as", e.target.value)}
                    />
                    <Textarea
                      placeholder="Review notes"
                      value={draft.review_notes ?? entry.review_notes ?? ""}
                      onChange={(e) => updateDraft(entry.id, "review_notes", e.target.value)}
                    />
                  </div>

                  <div className="flex gap-2">
                    <Button onClick={() => review(entry, true)} disabled={savingId === entry.id}>
                      {savingId === entry.id && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
                      Mark Reviewed
                    </Button>
                    <Button variant="outline" onClick={() => review(entry, false)} disabled={savingId === entry.id}>
                      Reopen
                    </Button>
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
}
