import { Link } from "react-router-dom";
import { MapPin, Ruler, TreePine, Leaf } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import HealthBadge from "./HealthBadge";

export default function TreeCard({ tree }) {
  return (
    <Link to={`/trees/${tree.id}`}>
      <Card className="hover:shadow-lg transition-all duration-300 hover:-translate-y-0.5 overflow-hidden group border-border">
        {/* Photo */}
        <div className="h-40 bg-gradient-to-br from-primary/10 to-accent overflow-hidden relative">
          {tree.photo_url ? (
            <img
              src={tree.photo_url}
              alt={tree.common_name}
              className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
            />
          ) : (
            <div className="w-full h-full flex items-center justify-center">
              <TreePine className="w-16 h-16 text-primary/30" />
            </div>
          )}
          <div className="absolute top-3 right-3">
            <HealthBadge status={tree.health_status} />
          </div>
        </div>

        <CardContent className="p-4">
          <h3 className="font-fraunces font-semibold text-foreground text-lg leading-tight">
            {tree.common_name}
          </h3>
          {tree.scientific_name && (
            <p className="text-muted-foreground text-xs italic mt-0.5">{tree.scientific_name}</p>
          )}

          <div className="mt-3 space-y-1.5">
            {tree.lat && tree.lng && (
              <div className="flex items-center gap-1.5 text-muted-foreground text-xs">
                <MapPin className="w-3 h-3" />
                <span>{tree.barangay || "Location tagged"}</span>
              </div>
            )}
            {tree.dbh_cm && (
              <div className="flex items-center gap-1.5 text-muted-foreground text-xs">
                <Ruler className="w-3 h-3" />
                <span>DBH: {tree.dbh_cm} cm</span>
              </div>
            )}
            {tree.carbon_kg && (
              <div className="flex items-center gap-1.5 text-muted-foreground text-xs">
                <Leaf className="w-3 h-3" />
                <span>Carbon: {tree.carbon_kg.toFixed(2)} kg</span>
              </div>
            )}
          </div>
        </CardContent>
      </Card>
    </Link>
  );
}
