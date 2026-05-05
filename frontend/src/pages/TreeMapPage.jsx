import { useQuery } from "@tanstack/react-query";
import { treesApi } from "@/api/trees";
import { MapContainer, TileLayer, Marker, Popup } from "react-leaflet";
import { Link } from "react-router-dom";
import HealthBadge from "@/components/trees/HealthBadge";
import { MapPin } from "lucide-react";
import "leaflet/dist/leaflet.css";
import L from "leaflet";

// Fix default marker icons (Leaflet + Vite issue)
delete L.Icon.Default.prototype._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-icon-2x.png",
  iconUrl:       "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-icon.png",
  shadowUrl:     "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-shadow.png",
});

// Panabo City, Davao del Norte
const DEFAULT_CENTER = [7.3047, 125.6856];

export default function TreeMapPage() {
  const { data: trees = [], isLoading } = useQuery({
    queryKey: ["trees"],
    queryFn: () => treesApi.list({ limit: 500 }),
  });

  const geoTrees = trees.filter((t) => t.lat && t.lng);

  return (
    <div className="p-8">
      <div className="mb-6">
        <h1 className="font-fraunces text-3xl font-semibold">Tree Map</h1>
        <p className="text-muted-foreground mt-1">
          {isLoading
            ? "Loading…"
            : `${geoTrees.length} of ${trees.length} trees GPS-tagged`}
        </p>
      </div>

      {/* Summary bar */}
      <div className="flex gap-4 mb-4 text-sm">
        {[
          { label: "Healthy", color: "bg-emerald-500" },
          { label: "Fair",    color: "bg-amber-500" },
          { label: "Poor",    color: "bg-red-500" },
        ].map(({ label, color }) => (
          <div key={label} className="flex items-center gap-1.5 text-muted-foreground">
            <span className={`w-3 h-3 rounded-full ${color}`} />
            {label}: {geoTrees.filter((t) => t.health_status === label).length}
          </div>
        ))}
      </div>

      <div className="rounded-xl overflow-hidden border border-border shadow-sm"
           style={{ height: "calc(100vh - 260px)" }}>
        <MapContainer
          center={DEFAULT_CENTER}
          zoom={13}
          style={{ height: "100%", width: "100%" }}
        >
          <TileLayer
            attribution='&copy; <a href="https://www.openstreetmap.org">OpenStreetMap</a>'
            url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
          />
          {geoTrees.map((tree) => (
            <Marker key={tree.id} position={[tree.lat, tree.lng]}>
              <Popup>
                <div className="min-w-[180px]">
                  {tree.photo_url && (
                    <img
                      src={tree.photo_url}
                      alt={tree.common_name}
                      className="w-full h-28 object-cover rounded mb-2"
                    />
                  )}
                  <p className="font-semibold">{tree.common_name}</p>
                  {tree.scientific_name && (
                    <p className="text-xs text-gray-500 italic">{tree.scientific_name}</p>
                  )}
                  <div className="flex items-center gap-1 text-xs text-gray-500 mt-1">
                    <MapPin className="w-3 h-3" />
                    {tree.barangay || "Panabo City"}
                  </div>
                  <div className="mt-2 flex items-center justify-between">
                    <HealthBadge status={tree.health_status} />
                    <Link
                      to={`/trees/${tree.id}`}
                      className="text-xs text-primary hover:underline"
                    >
                      View →
                    </Link>
                  </div>
                </div>
              </Popup>
            </Marker>
          ))}
        </MapContainer>
      </div>

      {geoTrees.length === 0 && !isLoading && (
        <div className="mt-4 text-center text-muted-foreground text-sm">
          No GPS-tagged trees yet. Enable location when adding trees to see them on the map.
        </div>
      )}
    </div>
  );
}
