import { Outlet } from "react-router-dom";
import { useState } from "react";
import Sidebar from "./Sidebar";
import { useAuth } from "@/lib/AuthContext";
import { Button } from "@/components/ui/button";
import { Menu } from "lucide-react";

export default function AppLayout() {
  const { user } = useAuth();
  const [sidebarOpen, setSidebarOpen] = useState(false);

  return (
    <div className="flex min-h-screen bg-background">
      <Sidebar
        user={user}
        mobileOpen={sidebarOpen}
        onMobileClose={() => setSidebarOpen(false)}
      />
      <header className="fixed left-0 right-0 top-0 z-40 flex h-14 items-center gap-3 border-b bg-background/95 px-4 backdrop-blur md:hidden">
        <Button
          type="button"
          variant="ghost"
          size="icon"
          onClick={() => setSidebarOpen(true)}
          aria-label="Open navigation"
        >
          <Menu className="h-5 w-5" />
        </Button>
        <div>
          <p className="font-fraunces text-lg font-semibold leading-none text-primary">TreeTrace</p>
          <p className="text-xs text-muted-foreground">Geo-Spatial Inventory</p>
        </div>
      </header>
      <main className="min-h-screen flex-1 overflow-x-hidden pt-14 md:ml-64 md:pt-0">
        <Outlet />
      </main>
    </div>
  );
}
