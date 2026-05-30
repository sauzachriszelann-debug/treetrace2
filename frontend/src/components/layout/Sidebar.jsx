import { Link, useLocation } from "react-router-dom";
import {
  LayoutDashboard, TreePine, Map, Plus, QrCode,
  Users, BarChart3, LogOut, Leaf, ScanLine, Globe,
  Network, WifiOff,
  FileText, SearchCheck, ClipboardCheck, X, Sprout, CloudUpload,
} from "lucide-react";
import { useAuth } from "@/lib/AuthContext";
import { useOfflineSync } from "@/hooks/useOfflineSync";
import { cn } from "@/lib/utils";

const navItems = [
  { label: "Dashboard", icon: LayoutDashboard, path: "/dashboard" },
  { label: "Tree Inventory", icon: TreePine, path: "/trees" },
  { label: "Tree Map", icon: Map, path: "/map" },
  { label: "Add Tree", icon: Plus, path: "/add-tree" },
  { label: "Community", icon: Network, path: "/community" },
  { label: "Planting", icon: Sprout, path: "/planting" },
  { label: "Evaluation", icon: ClipboardCheck, path: "/evaluation" },
  { label: "Field Sync", icon: CloudUpload, path: "/field-sync" },
  { label: "QR Scanner", icon: ScanLine, path: "/scan" },
  { label: "Public Portal", icon: Globe, path: "/public" },
];

const adminItems = [
  { label: "QR Generator", icon: QrCode, path: "/qr-manager" },
  { label: "Health Logs", icon: BarChart3, path: "/health-logs" },
  { label: "Unknown Review", icon: SearchCheck, path: "/unknown-species" },
  { label: "Reports & Tools", icon: FileText, path: "/reports" },
  { label: "Users", icon: Users, path: "/admin/users" },
];

export default function Sidebar({ user, mobileOpen = false, onMobileClose }) {
  const location = useLocation();
  const { logout } = useAuth();
  const { isOnline, queueLength } = useOfflineSync();
  const role = String(user?.role || "");
  const isAdmin = role === "admin" || role.includes("UserRole.admin");
  const isCitizen = role === "citizen" || role.includes("UserRole.citizen");
  const roleText = role.split(".").pop()?.replace("_", " ") || "field worker";
  const planText = isAdmin || role.includes("field_worker")
    ? "INSTITUTIONAL"
    : (user?.subscription_plan || "free").toUpperCase();
  const visibleNavItems = navItems
    .filter((item) => !(isCitizen && ["Add Tree", "Public Portal"].includes(item.label)))
    .map((item) => {
      if (isCitizen && item.label === "Tree Map") {
        return { ...item, path: "/public" };
      }
      return item;
    });

  return (
    <>
      {mobileOpen && (
        <button
          type="button"
          className="fixed inset-0 z-40 bg-black/45 md:hidden"
          aria-label="Close navigation"
          onClick={onMobileClose}
        />
      )}
      <aside
        className={cn(
          "fixed left-0 top-0 z-50 flex h-screen w-64 flex-col bg-sidebar shadow-2xl transition-transform duration-200 md:translate-x-0",
          mobileOpen ? "translate-x-0" : "-translate-x-full"
        )}
      >
        <div className="border-b border-sidebar-border px-6 py-6">
          <div className="flex items-center gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-sidebar-primary">
              <Leaf className="h-5 w-5 text-sidebar-primary-foreground" />
            </div>
            <div className="min-w-0">
              <h1 className="font-fraunces text-xl font-semibold leading-none text-sidebar-primary">
                TreeTrace
              </h1>
              <p className="mt-0.5 text-xs text-sidebar-foreground/50">Geo-Spatial Inventory</p>
            </div>
            <button
              type="button"
              className="ml-auto rounded-md p-1 text-sidebar-foreground/60 hover:bg-sidebar-accent hover:text-sidebar-foreground md:hidden"
              aria-label="Close navigation"
              onClick={onMobileClose}
            >
              <X className="h-5 w-5" />
            </button>
          </div>

          {!isOnline && (
            <div className="mt-3 flex items-center gap-2 rounded-lg bg-amber-500/20 px-2 py-1.5">
              <WifiOff className="h-3.5 w-3.5 text-amber-400" />
              <span className="text-xs text-amber-400">
                Offline{queueLength > 0 ? ` / ${queueLength} queued` : ""}
              </span>
            </div>
          )}
        </div>

        <nav className="flex-1 space-y-1 overflow-y-auto px-3 py-4">
          <div className="mb-2">
            <p className="mb-2 px-3 text-xs font-medium uppercase tracking-widest text-sidebar-foreground/40">
              Main
            </p>
            {visibleNavItems.map((item) => (
              <NavItem
                key={item.path}
                item={item}
                active={location.pathname === item.path}
                onClick={onMobileClose}
              />
            ))}
          </div>

          {isAdmin && (
            <div className="mt-4">
              <p className="mb-2 px-3 text-xs font-medium uppercase tracking-widest text-sidebar-foreground/40">
                Admin
              </p>
              {adminItems.map((item) => (
                <NavItem
                  key={item.path}
                  item={item}
                  active={location.pathname === item.path}
                  onClick={onMobileClose}
                />
              ))}
            </div>
          )}
        </nav>

        <div className="border-t border-sidebar-border px-4 py-4">
          <div className="mb-3 flex items-center gap-3">
            <div className="flex h-8 w-8 items-center justify-center rounded-full bg-sidebar-primary/20">
              <span className="text-xs font-semibold text-sidebar-primary">
                {user?.full_name?.charAt(0) || "U"}
              </span>
            </div>
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-medium text-sidebar-foreground">
                {user?.full_name || "User"}
              </p>
              <p className="truncate text-xs capitalize text-sidebar-foreground/50">
                {roleText} / {planText}
              </p>
            </div>
          </div>
          <button
            onClick={logout}
            className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm text-sidebar-foreground/60 transition-colors hover:bg-sidebar-accent hover:text-sidebar-foreground"
          >
            <LogOut className="h-4 w-4" />
            Sign out
          </button>
        </div>
      </aside>
    </>
  );
}

function NavItem({ item, active, onClick }) {
  const Icon = item.icon;
  return (
    <Link
      to={item.path}
      onClick={onClick}
      className={cn(
        "flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-all duration-150",
        active
          ? "bg-sidebar-primary text-sidebar-primary-foreground shadow-sm"
          : "text-sidebar-foreground/70 hover:bg-sidebar-accent hover:text-sidebar-foreground"
      )}
    >
      <Icon className="h-4 w-4 flex-shrink-0" />
      <span className="truncate">{item.label}</span>
    </Link>
  );
}
