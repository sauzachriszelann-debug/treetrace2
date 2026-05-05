import { Link } from "react-router-dom";
import { TreePine, ArrowLeft } from "lucide-react";
import { Button } from "@/components/ui/button";

export default function PageNotFound() {
  return (
    <div className="min-h-screen bg-background flex items-center justify-center">
      <div className="text-center">
        <TreePine className="w-20 h-20 mx-auto mb-6 text-primary/30" />
        <h1 className="font-fraunces text-5xl font-semibold text-foreground mb-2">404</h1>
        <p className="text-muted-foreground text-lg mb-6">Page not found</p>
        <Link to="/">
          <Button className="flex items-center gap-2 mx-auto">
            <ArrowLeft className="w-4 h-4" />
            Back to Dashboard
          </Button>
        </Link>
      </div>
    </div>
  );
}
