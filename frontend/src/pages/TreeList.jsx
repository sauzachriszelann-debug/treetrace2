import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { treesApi } from "@/api/trees";
import TreeCard from "@/components/trees/TreeCard";
import { Input } from "@/components/ui/input";
import {
  Select, SelectContent, SelectItem,
  SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import { Search, Plus, TreePine } from "lucide-react";
import { Link } from "react-router-dom";
import { useSearchParams } from "react-router-dom";
import { useAuth } from "@/lib/AuthContext";

export default function TreeList() {
  const [searchParams, setSearchParams] = useSearchParams();
  const [search, setSearch]             = useState("");
  const [healthFilter, setHealthFilter] = useState(searchParams.get("health") || "all");
  const { user } = useAuth();
  const canAddOfficialTree = user?.role !== "citizen";

  const { data: trees = [], isLoading } = useQuery({
    queryKey: ["trees"],
    queryFn: () => treesApi.list({ limit: 500 }),
  });

  const filtered = trees.filter((t) => {
    const matchSearch =
      t.common_name?.toLowerCase().includes(search.toLowerCase()) ||
      t.scientific_name?.toLowerCase().includes(search.toLowerCase()) ||
      t.barangay?.toLowerCase().includes(search.toLowerCase());
    const matchHealth = healthFilter === "attention"
      ? t.health_status === "Fair" || t.health_status === "Poor"
      : healthFilter === "all" || t.health_status === healthFilter;
    return matchSearch && matchHealth;
  });

  return (
    <div className="p-4 sm:p-6 lg:p-8">
      <div className="mb-6 flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0">
          <h1 className="font-fraunces text-2xl font-semibold sm:text-3xl">Tree Inventory</h1>
          <p className="text-muted-foreground mt-1">{trees.length} trees recorded</p>
        </div>
        {canAddOfficialTree && (
          <Link to="/add-tree" className="w-full sm:w-auto">
            <Button className="flex w-full items-center gap-2 sm:w-auto">
              <Plus className="w-4 h-4" />
              Add Tree
            </Button>
          </Link>
        )}
      </div>

      {/* Filters */}
      <div className="mb-6 flex flex-col gap-3 sm:flex-row">
        <div className="relative flex-1 sm:max-w-sm">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
          <Input
            placeholder="Search by name, species, barangay…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="pl-9"
          />
        </div>
        <Select
          value={healthFilter}
          onValueChange={(value) => {
            setHealthFilter(value);
            setSearchParams(value === "all" ? {} : { health: value });
          }}
        >
          <SelectTrigger className="w-full sm:w-40">
            <SelectValue placeholder="Health Status" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Status</SelectItem>
            <SelectItem value="Healthy">Healthy</SelectItem>
            <SelectItem value="Fair">Fair</SelectItem>
            <SelectItem value="Poor">Poor</SelectItem>
            <SelectItem value="attention">Need Attention</SelectItem>
          </SelectContent>
        </Select>
      </div>

      {isLoading ? (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
          {[1, 2, 3, 4, 5, 6].map((i) => (
            <div key={i} className="h-64 rounded-xl bg-muted animate-pulse" />
          ))}
        </div>
      ) : filtered.length === 0 ? (
        <div className="text-center py-20 text-muted-foreground">
          <TreePine className="w-16 h-16 mx-auto mb-4 opacity-20" />
          <p className="font-fraunces text-xl">No trees found</p>
          <p className="text-sm mt-1">Try adjusting your search or add a new tree</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
          {filtered.map((tree) => (
            <TreeCard key={tree.id} tree={tree} />
          ))}
        </div>
      )}
    </div>
  );
}
