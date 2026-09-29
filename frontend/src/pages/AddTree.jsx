import { useState } from "react";
import { useNavigate, Link } from "react-router-dom";
import { useQueryClient } from "@tanstack/react-query";
import { treesApi } from "@/api/trees";
import TreeForm from "@/components/trees/TreeForm";
import { Button } from "@/components/ui/button";
import { ArrowLeft } from "lucide-react";
import { toast } from "sonner";
import { useAuth } from "@/lib/AuthContext";
import { useOfflineSync } from "@/hooks/useOfflineSync";

export default function AddTree() {
  const navigate = useNavigate();
  const qc       = useQueryClient();
  const [loading, setLoading] = useState(false);
  const { user } = useAuth();
  const { isOnline, addToQueue } = useOfflineSync();

  if (user?.role === "citizen") {
    return (
      <div className="mx-auto max-w-5xl p-4 sm:p-6 lg:p-8">
        <Link
          to="/ai-identify"
          className="inline-flex items-center gap-2 text-muted-foreground hover:text-foreground text-sm mb-6 transition-colors"
        >
          <ArrowLeft className="w-4 h-4" />
          Back to AI Identify
        </Link>

        <div className="bg-card border border-border rounded-xl p-5 shadow-sm sm:p-7">
          <h1 className="font-fraunces text-2xl font-semibold sm:text-3xl">Official Inventory Restricted</h1>
          <p className="text-muted-foreground mt-3">
            Citizen accounts cannot add official inventory trees directly.
            Please use AI Identify and submit the species for expert review.
            Admins or field workers will verify approved records.
          </p>
          <Button className="mt-6 w-full sm:w-auto" onClick={() => navigate("/ai-identify")}>
            Submit Through AI Identify
          </Button>
        </div>
      </div>
    );
  }

  const handleSubmit = async (data) => {
    setLoading(true);
    if (!isOnline) {
      addToQueue({ type: "CREATE_TREE", payload: data });
      setLoading(false);
      navigate("/field-sync");
      return;
    }

    try {
      const newTree = await treesApi.create(data);
      qc.invalidateQueries({ queryKey: ["trees"] });
      toast.success("Tree record created successfully!");
      navigate(`/trees/${newTree.id}`);
    } catch (err) {
      if (!err?.response) {
        addToQueue({ type: "CREATE_TREE", payload: data });
        toast.info("Connection failed. Saved to Field Sync instead.");
        navigate("/field-sync");
        return;
      }
      toast.error(err?.response?.data?.detail || "Failed to create tree record.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="mx-auto max-w-5xl p-4 sm:p-6 lg:p-8">
      <Link
        to="/trees"
        className="inline-flex items-center gap-2 text-muted-foreground hover:text-foreground text-sm mb-6 transition-colors"
      >
        <ArrowLeft className="w-4 h-4" />
        Back to Inventory
      </Link>

      <div className="mb-6">
        <h1 className="font-fraunces text-2xl font-semibold sm:text-3xl">Add New Tree</h1>
        <p className="text-muted-foreground mt-1">
          Record a new tree entry with GPS location and measurements
        </p>
      </div>

      <div className="bg-card border border-border rounded-xl p-5 shadow-sm sm:p-7 lg:p-8">
        <TreeForm onSubmit={handleSubmit} loading={loading} />
      </div>
    </div>
  );
}
