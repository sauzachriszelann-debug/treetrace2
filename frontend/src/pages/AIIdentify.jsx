import { useState } from "react";
import { useNavigate, Link } from "react-router-dom";
import { useQueryClient } from "@tanstack/react-query";
import { treesApi } from "@/api/trees";
import { aiApi } from "@/api/ai";
import TreeForm from "@/components/trees/TreeForm";
import { useAuth } from "@/lib/AuthContext";
import { ArrowLeft } from "lucide-react";
import { toast } from "sonner";

export default function AIIdentify() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { user } = useAuth();
  const [loading, setLoading] = useState(false);
  const isCitizen = user?.role === "citizen";

  const handleSubmit = async (data) => {
    setLoading(true);
    try {
      if (isCitizen) {
        await aiApi.submitUnknown({
          photo_url: data.photo_url || "",
          barangay: data.barangay,
          location_description: [data.lat, data.lng].filter(Boolean).join(", "),
          possible_name: data.common_name,
          submitter_notes: data.notes || "Submitted from web AI scanner.",
          ai_candidates: [],
        });
        toast.success("Submitted for expert review.");
        navigate("/public");
        return;
      }

      const newTree = await treesApi.create(data);
      queryClient.invalidateQueries({ queryKey: ["trees"] });
      toast.success("Tree submitted successfully.");
      navigate(`/trees/${newTree.id}`);
    } catch (error) {
      toast.error(error?.response?.data?.detail || "Failed to submit tree.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="p-8 max-w-4xl mx-auto">
      <Link
        to="/trees"
        className="inline-flex items-center gap-2 text-muted-foreground hover:text-foreground text-sm mb-6 transition-colors"
      >
        <ArrowLeft className="w-4 h-4" />
        Back to Inventory
      </Link>

      <div className="mb-6">
        <h1 className="font-fraunces text-3xl font-semibold">AI Identify a Tree</h1>
        <p className="text-muted-foreground mt-2 max-w-2xl">
          Upload a photo and let the AI suggest the species, diameter, and height.
          {isCitizen
            ? "Citizen scans are submitted for expert review before they become official records."
            : "Once the tree is identified, submit it to the official inventory."}
        </p>
      </div>

      <div className="bg-card border border-border rounded-xl p-6 shadow-sm">
        <TreeForm
          onSubmit={handleSubmit}
          loading={loading}
          submitLabel={isCitizen ? "Submit for Expert Review" : "Save Tree Record"}
          savingLabel={isCitizen ? "Submitting…" : "Saving…"}
        />
      </div>
    </div>
  );
}
