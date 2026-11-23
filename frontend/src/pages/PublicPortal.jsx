import { PANABO_BARANGAYS } from "@/lib/panaboBarangays";
import { useState, useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { publicApiService } from "@/api/publicApi";
import { MapContainer, TileLayer, Marker, Popup, LayersControl, LayerGroup } from "react-leaflet";
import { Link, useNavigate } from "react-router-dom";
import HealthBadge from "@/components/trees/HealthBadge";
import { Leaf, TreePine, MapPin, Search, ScanLine, Map as MapIcon, List, ChevronRight } from "lucide-react";
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
const STATUS_COLORS = { "Not assessed": "#94a3b8", Healthy: "#10b981", Fair: "#f59e0b", Poor: "#ef4444" };

export function healthIcon(status) {
  const color = STATUS_COLORS[status] || "#94a3b8";
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
  const [barangayFilter, setBarangay] = useState("all");
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
      const matchBarangay = barangayFilter === "all" || t.barangay?.trim().toLowerCase() === barangayFilter;
      return matchSearch && matchStatus && matchBarangay;
    });
  }, [allTrees, search, statusFilter, barangayFilter]);

  const barangays = useMemo(() => {
    const names = new Map(PANABO_BARANGAYS.map(name => [name.toLowerCase(), name]));
    for (const tree of allTrees) {
      const name = tree.barangay?.trim();
      if (name && !names.has(name.toLowerCase())) names.set(name.toLowerCase(), name);
    }
    return [...names.values()].sort((a, b) => a.localeCompare(b));
  }, [allTrees]);

  const geoTrees = filtered.filter((t) => t.lat && t.lng);
  const totalCarbon = allTrees.reduce((s, t) => s + (t.carbon_kg || 0), 0);
  const healthy = allTrees.filter((t) => t.health_status === "Healthy").length;
  const fair    = allTrees.filter((t) => t.health_status === "Fair").length;
  const poor    = allTrees.filter((t) => t.health_status === "Poor").length;

  return (
    <div className="min-h-screen max-w-full overflow-x-hidden bg-background">
      <header className="border-b border-white/10 bg-[#1e3a2b] text-white">
        <div className="mx-auto grid max-w-7xl gap-6 px-4 py-7 sm:px-6 lg:grid-cols-[1.1fr_1fr] lg:items-center lg:gap-12 lg:px-8 lg:py-9">
          <div>
            <div className="mb-3 flex items-center gap-2 text-sm font-medium text-[#d5e5ac]">
              <Leaf className="h-4 w-4" aria-hidden="true" />
              TreeTrace <span className="text-white/30">/</span> Public Portal
            </div>
            <h1 className="font-fraunces text-3xl font-semibold leading-tight sm:text-4xl">
              Panabo City Tree Inventory
            </h1>
            <p className="mt-3 max-w-xl text-sm leading-relaxed text-white/75 sm:text-base">
              Explore tree locations, health, and carbon stock. Select a tree or scan its QR code to view its profile.
            </p>
          </div>
          <div>
            <dl className="grid grid-cols-3 gap-2 sm:gap-3">
              {[
                { label: "Total trees", value: allTrees.length },
                { label: "Geotagged", value: allTrees.filter(t => t.lat && t.lng).length },
                { label: "Carbon stock", value: `${(totalCarbon / 1000).toFixed(2)} t` },
              ].map(({ label, value }) => (
                <div key={label} className="rounded-xl border border-white/10 bg-white/[0.06] px-3 py-4 sm:px-4">
                  <dt className="text-xs text-white/65">{label}</dt>
                  <dd className="mt-2 text-xl font-semibold tabular-nums sm:text-2xl">{isLoading ? "—" : value}</dd>
                </div>
              ))}
            </dl>
            <p className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-xs text-white/75">
              <span>Healthy <strong className="ml-1 text-emerald-300">{healthy}</strong></span>
              <span>Fair <strong className="ml-1 text-amber-300">{fair}</strong></span>
              <span>Poor <strong className="ml-1 text-red-300">{poor}</strong></span>
              <span>Not assessed <strong className="ml-1 text-slate-200">{allTrees.filter(t => t.health_status === "Not assessed").length}</strong></span>
            </p>
          </div>
        </div>
      </header>

      {/* Controls bar */}
      <div className="mx-auto max-w-7xl px-4 pt-5 sm:px-6 lg:px-8">
        <div className="space-y-4 rounded-2xl border border-border bg-white p-4 shadow-sm sm:p-5">
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-[minmax(180px,1fr)_13rem_11rem_auto]">
            <div className="relative col-span-2 lg:col-span-1 min-w-0">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
              <Input
                className="h-11 pl-9 bg-background/50"
                aria-label="Search trees"
                placeholder="Search name, species, or barangay..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
            </div>
            <Select value={barangayFilter} onValueChange={setBarangay}>
              <SelectTrigger aria-label="Filter by barangay" className="h-11 min-w-0 w-full bg-background/50">
                <SelectValue placeholder="All Barangays" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All Barangays</SelectItem>
                {barangays.map(name => <SelectItem key={name.toLowerCase()} value={name.toLowerCase()}>{name}</SelectItem>)}
              </SelectContent>
            </Select>
            <Select value={statusFilter} onValueChange={setStatus}>
              <SelectTrigger aria-label="Filter by health status" className="h-11 min-w-0 w-full bg-background/50">
                <SelectValue placeholder="All Status" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All Status</SelectItem>
                <SelectItem value="Not assessed">Not assessed</SelectItem>
                  <SelectItem value="Healthy">Healthy</SelectItem>
                <SelectItem value="Fair">Fair</SelectItem>
                <SelectItem value="Poor">Poor</SelectItem>
              </SelectContent>
            </Select>
            <Button
              className="col-span-2 flex h-11 w-full items-center justify-center gap-2 whitespace-nowrap bg-[#2d5a27] text-white hover:bg-[#234820] lg:col-span-1"
              onClick={() => navigate("/scan")}
            >
              <ScanLine className="w-4 h-4" />
              Scan QR
            </Button>
          </div>

          <div className="flex flex-col gap-3 border-t border-border pt-4 xl:flex-row xl:items-center xl:justify-between">
            <div className="flex w-fit items-center gap-1 rounded-lg bg-muted/60 p-1">
              <button
                aria-pressed={view === "map"}
                onClick={() => setView("map")}
                  className={`flex items-center gap-2 px-3 py-1.5 rounded-md text-sm font-medium whitespace-nowrap transition-colors ${
                  view === "map" ? "bg-white shadow-sm text-foreground border border-border" : "text-muted-foreground hover:text-foreground"
                }`}
              >
                <MapIcon className="w-4 h-4" /> Map View
              </button>
              <button
                aria-pressed={view === "list"}
                onClick={() => setView("list")}
                  className={`flex items-center gap-2 px-3 py-1.5 rounded-md text-sm font-medium whitespace-nowrap transition-colors ${
                  view === "list" ? "bg-white shadow-sm text-foreground border border-border" : "text-muted-foreground hover:text-foreground"
                }`}
              >
                <List className="w-4 h-4" /> List View
              </button>
            </div>
            <div className="flex flex-wrap items-center gap-x-4 gap-y-2 text-xs sm:text-sm">
              <span className="flex items-center gap-1.5 whitespace-nowrap text-muted-foreground">
                <span className="w-2.5 h-2.5 rounded-full bg-emerald-500 inline-block" /> Healthy
              </span>
              <span className="flex items-center gap-1.5 whitespace-nowrap text-muted-foreground">
                <span className="w-2.5 h-2.5 rounded-full bg-amber-500 inline-block" /> Fair
              </span>
              <span className="flex items-center gap-1.5 whitespace-nowrap text-muted-foreground">
                <span className="w-2.5 h-2.5 rounded-full bg-red-500 inline-block" /> Poor
              </span>
              <span className="flex items-center gap-1.5 whitespace-nowrap text-muted-foreground">
                <span className="w-2.5 h-2.5 rounded-full bg-slate-400 inline-block" /> Not assessed
              </span>
              <span className="whitespace-nowrap text-muted-foreground text-xs">
                {view === "map" ? geoTrees.length : filtered.length} trees {view === "map" ? "mapped" : "found"}
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="mx-auto w-full max-w-7xl px-4 py-5 sm:px-6 lg:px-8">
        {isLoading ? (
          <div className="flex items-center justify-center h-64 text-muted-foreground">
            <div className="text-center">
              <div className="w-8 h-8 border-4 border-primary/20 border-t-primary rounded-full animate-spin mx-auto mb-2" />
              Loading trees…
            </div>
          </div>
        ) : view === "map" ? (
          <div className="relative z-0 overflow-hidden rounded-2xl border border-border shadow-sm" style={{ height: "clamp(380px, 62vh, 760px)" }}>
            {geoTrees.length === 0 ? (
              <div className="w-full h-full flex items-center justify-center bg-muted text-muted-foreground">
                <div className="text-center">
                  <MapPin className="w-10 h-10 mx-auto mb-2 opacity-30" />
                  <p>No GPS-tagged trees match your filter.</p>
                </div>
              </div>
            ) : (
              <MapContainer
                center={DEFAULT_CENTER}
                zoom={13}
                minZoom={3}
                maxZoom={20}
                style={{ height: "100%", width: "100%" }}
              >
                <LayersControl position="topright">
                  <LayersControl.BaseLayer checked name="Street map">
                    <TileLayer
                      attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
                      url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                      maxZoom={20}
                    />
                  </LayersControl.BaseLayer>
                  <LayersControl.BaseLayer name="Satellite">
                    <LayerGroup>
                      <TileLayer
                        attribution='Imagery &copy; <a href="https://www.esri.com/">Esri</a>, Maxar, Earthstar Geographics, and the GIS User Community'
                        url="https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
                        maxNativeZoom={19}
                        maxZoom={20}
                      />
                      <TileLayer
                        attribution='Labels &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>'
                        url={`https://{s}.basemaps.cartocdn.com/rastertiles/voyager_only_labels/{z}/{x}/{y}{r}.png?key=${import.meta.env.VITE_CARTO_API_KEY || ""}`}
                        maxZoom={20}
                        zIndex={2}
                      />
                    </LayerGroup>
                  </LayersControl.BaseLayer>
                </LayersControl>
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
          <div className="grid gap-3 md:grid-cols-2">
            {filtered.length === 0 ? (
              <div className="col-span-full rounded-2xl border border-dashed border-border py-16 text-center text-muted-foreground">
                <TreePine className="w-12 h-12 mx-auto mb-3 opacity-20" />
                <p>No trees match your search.</p>
              </div>
            ) : (
              filtered.map((tree) => (
                <Link
                  key={tree.id}
                  to={`/public/tree/${tree.id}`}
                  className="group flex items-start gap-4 rounded-xl border border-border bg-white p-4 transition-all hover:border-[#2d5a27]/30 hover:shadow-sm"
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
                    <p className="break-words font-semibold text-foreground">{tree.common_name}</p>
                    {tree.scientific_name && (
                      <p className="break-words text-xs italic text-muted-foreground">{tree.scientific_name}</p>
                    )}
                    <div className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground">
                      {tree.barangay && (
                        <span className="flex min-w-0 items-start gap-0.5">
                          <MapPin className="w-3 h-3" />{tree.barangay}
                        </span>
                      )}
                      {tree.dbh_cm && <span>DBH: {tree.dbh_cm} cm</span>}
                    </div>
                    <div className="mt-3"><HealthBadge status={tree.health_status} /></div>
                  </div>
                  <ChevronRight className="mt-1 h-4 w-4 shrink-0 text-muted-foreground transition-colors group-hover:text-[#2d5a27]" />
                </Link>
              ))
            )}
          </div>
        )}
      </div>
    </div>
  );
}
