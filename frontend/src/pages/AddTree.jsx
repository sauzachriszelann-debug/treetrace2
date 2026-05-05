import { useState } from "react";
import { useNavigate, Link } from "react-router-dom";
import { useQueryClient } from "@tanstack/react-query";
import { treesApi } from "@/api/trees";
import TreeForm from "@/components/trees/TreeForm";
import { ArrowLeft } from "lucide-react";
import { toast } from "sonner";

export default function AddTree() {
  const navigate = useNavigate();
  const qc       = useQueryClient();
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (data) => {
    setLoading(true);
    try {
      const newTree = await treesApi.create(data);
      qc.invalidateQueries({ queryKey: ["trees"] });
      toast.success("Tree record created successfully!");
      navigate(`/trees/${newTree.id}`);
    } catch (err) {
      toast.error(err?.response?.data?.detail || "Failed to create tree record.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="p-8 max-w-2xl mx-auto">
      <Link
        to="/trees"
        className="inline-flex items-center gap-2 text-muted-foreground hover:text-foreground text-sm mb-6 transition-colors"
      >
        <ArrowLeft className="w-4 h-4" />
        Back to Inventory
      </Link>

      <div className="mb-6">
        <h1 className="font-fraunces text-3xl font-semibold">Add New Tree</h1>
        <p className="text-muted-foreground mt-1">
          Record a new tree entry with GPS location and measurements
        </p>
      </div>

      <div className="bg-card border border-border rounded-xl p-6 shadow-sm">
        <TreeForm onSubmit={handleSubmit} loading={loading} />
      </div>
    </div>
  );
}
