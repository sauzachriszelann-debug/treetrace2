import { useState, useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { publicApiService } from "@/api/publicApi";
import { MapContainer, TileLayer, Marker, Popup } from "react-leaflet";
import { Link, useNavigate } from "react-router-dom";
import HealthBadge from "@/components/trees/HealthBadge";
import { Leaf, TreePine, MapPin, Search, ScanLine, Map, List, ChevronRight } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import "leaflet/dist/leaflet.css";
import L from "leaflet";

delete L.Icon.Default.prototype._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-icon-2x.png",
  iconUrl:       "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-icon.png",
  shadowUrl:     "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-shadow.png",
});

const DEFAULT_CENTER = [7.3047, 125.6856];
const STATUS_COLORS = { Healthy: "#10b981", Fair: "#f59e0b", Poor: "#ef4444" };

function healthIcon(status) {
  const color = STATUS_COLORS[status] || "#10b981";
  return L.divIcon({
    className: "custom-leaflet-marker",
    html: `
      <div style="filter: drop-shadow(0px 3px 6px rgba(0,0,0,0.25)); display: flex; align-items: center; justify-content: center; position: relative;">
        <!-- Pin Shape -->
        <svg xmlns="http://www.w3.org/2000/svg" width="30" height="38" viewBox="0 0 24 30" fill="${color}">
          <path d="M12 0C5.4 0 0 5.4 0 12c0 8.4 12 18 12 18s12-9.6 12-18c0-6.6-5.4-12-12-12z" />
          <!-- Inner Circle -->
          <circle cx="12" cy="12" r="5.5" fill="white" />
        </svg>
        <!-- Leaf icon centered in white circle -->
        <div style="position: absolute; top: 8px; left: 8px; color: ${color}; width: 14px; height: 14px; display: flex; align-items: center; justify-content: center;">
          <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
            <path d="M11 20A7 7 0 0 1 9.8 6.1C15.5 5 17 4.48 19 2c1 2 2 3.5 1 9.8a7 7 0 0 1-9 8.2Z"/>
            <path d="M9 22v-4h-4"/>
          </svg>
        </div>
      </div>
    `,
    iconSize: [30, 38],
    iconAnchor: [15, 38],
    popupAnchor: [0, -36],
  });
}

export default function PublicPortal() {
  const navigate = useNavigate();
  const [search, setSearch]     = useState("");
  const [statusFilter, setStatus] = useState("all");
  const [view, setView]         = useState("map");

  const { data: allTrees = [], isLoading } = useQuery({
    queryKey: ["public-trees-all"],
    queryFn:  publicApiService.listAllTrees,
  });

  const filtered = useMemo(() => {
    return allTrees.filter((t) => {
      const q = search.toLowerCase();
      const matchSearch =
        !q ||
        t.common_name?.toLowerCase().includes(q) ||
        t.scientific_name?.toLowerCase().includes(q) ||
        t.barangay?.toLowerCase().includes(q);
      const matchStatus =
        statusFilter === "all" || t.health_status === statusFilter;
      return matchSearch && matchStatus;
    });
  }, [allTrees, search, statusFilter]);

  const geoTrees = filtered.filter((t) => t.lat && t.lng);
  const totalCarbon = allTrees.reduce((s, t) => s + (t.carbon_kg || 0), 0);
  const healthy = allTrees.filter((t) => t.health_status === "Healthy").length;
  const fair    = allTrees.filter((t) => t.health_status === "Fair").length;
  const poor    = allTrees.filter((t) => t.health_status === "Poor").length;

  return (
    <div className="min-h-screen bg-background">
      {/* Hero header */}
      <header className="bg-[#2d5a27] text-white px-8 pt-8 pb-10">
        <div className="max-w-5xl mx-auto">
          <div className="inline-flex items-center gap-2 bg-white/15 rounded-lg px-3 py-1.5 mb-5">
            <div className="w-6 h-6 bg-white/20 rounded-md flex items-center justify-center">
              <Leaf className="w-3.5 h-3.5 text-white" />
            </div>
            <span className="text-white/90 text-sm font-medium">TreeTrace · Public Portal</span>
          </div>
          <h1 className="font-fraunces text-4xl md:text-5xl font-bold leading-tight mb-3">
            Panabo City<br />Tree Inventory
          </h1>
          <p className="text-white/75 text-base max-w-lg mb-6">
            Explore the geo-spatial tree inventory of Panabo City. View health status,
            GPS locations, carbon stock data, and scan QR codes to access individual tree profiles.
          </p>
          <div className="flex flex-wrap gap-x-6 gap-y-1 text-sm text-white/80">
            <span>Total Trees: <strong className="text-white">{allTrees.length}</strong></span>
            <span>Healthy: <strong className="text-emerald-300">{healthy}</strong></span>
            <span>Fair: <strong className="text-amber-300">{fair}</strong></span>
            <span>Poor: <strong className="text-red-300">{poor}</strong></span>
            <span>Carbon Stock: <strong className="text-white">{(totalCarbon / 1000).toFixed(2)} t</strong></span>
          </div>
        </div>
      </header>

      {/* Controls bar */}
      <div className="bg-[#f5f5f0] border-b border-border px-8 py-4">
        <div className="max-w-5xl mx-auto space-y-3">
          <div className="flex flex-wrap items-center gap-3">
            <div className="relative flex-1 min-w-[220px]">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
              <Input
                className="pl-9 bg-white"
                placeholder="Search by name, species, barangay..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
            </div>
            <Select value={statusFilter} onValueChange={setStatus}>
              <SelectTrigger className="w-40 bg-white">
                <SelectValue placeholder="All Status" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All Status</SelectItem>
                <SelectItem value="Healthy">Healthy</SelectItem>
                <SelectItem value="Fair">Fair</SelectItem>
                <SelectItem value="Poor">Poor</SelectItem>
              </SelectContent>
            </Select>
            <Button
              className="bg-[#2d5a27] hover:bg-[#234820] text-white flex items-center gap-2"
              onClick={() => navigate("/scan")}
            >
              <ScanLine className="w-4 h-4" />
              Scan QR
            </Button>
          </div>

          <div className="flex items-center justify-between">
            <div className="flex items-center gap-1 bg-white rounded-lg border border-border p-1">
              <button
                onClick={() => setView("map")}
                className={`flex items-center gap-2 px-3 py-1.5 rounded-md text-sm font-medium transition-colors ${
                  view === "map" ? "bg-white shadow-sm text-foreground border border-border" : "text-muted-foreground hover:text-foreground"
                }`}
              >
                <Map className="w-4 h-4" /> Map View
              </button>
              <button
                onClick={() => setView("list")}
                className={`flex items-center gap-2 px-3 py-1.5 rounded-md text-sm font-medium transition-colors ${
                  view === "list" ? "bg-white shadow-sm text-foreground border border-border" : "text-muted-foreground hover:text-foreground"
                }`}
              >
                <List className="w-4 h-4" /> List View
              </button>
            </div>
            <div className="flex items-center gap-4 text-sm">
              <span className="flex items-center gap-1.5 text-muted-foreground">
                <span className="w-2.5 h-2.5 rounded-full bg-emerald-500 inline-block" /> Healthy
              </span>
              <span className="flex items-center gap-1.5 text-muted-foreground">
                <span className="w-2.5 h-2.5 rounded-full bg-amber-500 inline-block" /> Fair
              </span>
              <span className="flex items-center gap-1.5 text-muted-foreground">
                <span className="w-2.5 h-2.5 rounded-full bg-red-500 inline-block" /> Poor
              </span>
              <span className="text-muted-foreground text-xs">
                {view === "map" ? geoTrees.length : filtered.length} trees {view === "map" ? "mapped" : "found"}
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="max-w-5xl mx-auto px-8 py-6">
        {isLoading ? (
          <div className="flex items-center justify-center h-64 text-muted-foreground">
            <div className="text-center">
              <div className="w-8 h-8 border-4 border-primary/20 border-t-primary rounded-full animate-spin mx-auto mb-2" />
              Loading trees…
            </div>
          </div>
        ) : view === "map" ? (
          <div className="rounded-xl overflow-hidden border border-border shadow-sm" style={{ height: "60vh" }}>
            {geoTrees.length === 0 ? (
              <div className="w-full h-full flex items-center justify-center bg-muted text-muted-foreground">
                <div className="text-center">
                  <MapPin className="w-10 h-10 mx-auto mb-2 opacity-30" />
                  <p>No GPS-tagged trees match your filter.</p>
                </div>
              </div>
            ) : (
              <MapContainer center={DEFAULT_CENTER} zoom={13} style={{ height: "100%", width: "100%" }}>
                <TileLayer
                  attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>'
                  url="https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png"
                />
                {geoTrees.map((tree) => (
                  <Marker key={tree.id} position={[tree.lat, tree.lng]} icon={healthIcon(tree.health_status)}>
                    <Popup>
                      <div className="min-w-[180px]">
                        {tree.photo_url && (
                          <img src={tree.photo_url} alt={tree.common_name} className="w-full h-28 object-cover rounded mb-2" />
                        )}
                        <p className="font-semibold text-sm">{tree.common_name}</p>
                        {tree.scientific_name && (
                          <p className="text-xs text-gray-500 italic">{tree.scientific_name}</p>
                        )}
                        {tree.barangay && (
                          <p className="text-xs text-gray-500 flex items-center gap-1 mt-0.5">
                            <MapPin className="w-3 h-3" />{tree.barangay}
                          </p>
                        )}
                        <div className="mt-2 flex items-center justify-between">
                          <HealthBadge status={tree.health_status} />
                          <Link to={`/public/tree/${tree.id}`} className="text-xs text-[#2d5a27] font-medium hover:underline">
                            View profile →
                          </Link>
                        </div>
                      </div>
                    </Popup>
                  </Marker>
                ))}
              </MapContainer>
            )}
          </div>
        ) : (
          <div className="space-y-2">
            {filtered.length === 0 ? (
              <div className="text-center py-16 text-muted-foreground">
                <TreePine className="w-12 h-12 mx-auto mb-3 opacity-20" />
                <p>No trees match your search.</p>
              </div>
            ) : (
              filtered.map((tree) => (
                <Link
                  key={tree.id}
                  to={`/public/tree/${tree.id}`}
                  className="flex items-center gap-4 bg-white border border-border rounded-xl p-4 hover:shadow-sm hover:border-[#2d5a27]/30 transition-all group"
                >
                  <div className="w-14 h-14 rounded-lg overflow-hidden flex-shrink-0 bg-muted">
                    {tree.photo_url ? (
                      <img src={tree.photo_url} alt={tree.common_name} className="w-full h-full object-cover" />
                    ) : (
                      <div className="w-full h-full flex items-center justify-center">
                        <TreePine className="w-7 h-7 text-muted-foreground/40" />
                      </div>
                    )}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="font-semibold text-foreground truncate">{tree.common_name}</p>
                    {tree.scientific_name && (
                      <p className="text-xs text-muted-foreground italic truncate">{tree.scientific_name}</p>
                    )}
                    <div className="flex items-center gap-2 mt-0.5 text-xs text-muted-foreground">
                      {tree.barangay && (
                        <span className="flex items-center gap-0.5">
                          <MapPin className="w-3 h-3" />{tree.barangay}
                        </span>
                      )}
                      {tree.dbh_cm && <span>DBH: {tree.dbh_cm} cm</span>}
                    </div>
                  </div>
                  <div className="flex items-center gap-3 flex-shrink-0">
                    <HealthBadge status={tree.health_status} />
                    <ChevronRight className="w-4 h-4 text-muted-foreground group-hover:text-[#2d5a27] transition-colors" />
                  </div>
                </Link>
              ))
            )}
          </div>
        )}
      </div>
    </div>
  );
}
