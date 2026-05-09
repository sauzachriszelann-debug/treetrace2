import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { Toaster } from "sonner";

// Layout
import AppLayout from "@/components/layout/AppLayout";
import ProtectedRoute from "@/components/ProtectedRoute";

// Auth pages (no layout)
import Login    from "@/pages/Login";
import Register from "@/pages/Register";

// App pages (with sidebar layout)
import Dashboard         from "@/pages/Dashboard";
import TreeList          from "@/pages/TreeList";
import TreeDetail        from "@/pages/TreeDetail";
import AddTree           from "@/pages/AddTree";
import TreeMapPage       from "@/pages/TreeMapPage";
import QRManager         from "@/pages/QRManager";
import ScanQR            from "@/pages/ScanQR";
import HealthLogs        from "@/pages/HealthLogs";
import AdminUsers        from "@/pages/AdminUsers";
import PublicPortal      from "@/pages/PublicPortal";
import AIIdentify        from "@/pages/AIIdentify";
import CommunityStructure from "@/pages/CommunityStructure";
import Upgrade           from "@/pages/Upgrade";
import UnknownSpeciesReview from "@/pages/UnknownSpeciesReview";
import ReportsAndTools from "@/pages/ReportsAndTools";

// Public pages (no auth, no sidebar)
import PublicTreeProfile from "@/pages/PublicTreeProfile";
import PageNotFound      from "@/lib/PageNotFound";

export default function App() {
  return (
    <BrowserRouter>
      <Toaster richColors position="top-right" />
      <Routes>
        {/* ── Public (no auth required) ── */}
        <Route path="/login"    element={<Login />} />
        <Route path="/register" element={<Register />} />
        <Route path="/public/tree/:id" element={<PublicTreeProfile />} />

        {/* ── Protected app shell ── */}
        <Route
          element={
            <ProtectedRoute>
              <AppLayout />
            </ProtectedRoute>
          }
        >
          <Route index              element={<Dashboard />} />
          <Route path="trees"       element={<TreeList />} />
          <Route path="trees/:id"   element={<TreeDetail />} />
          <Route path="add-tree"    element={<AddTree />} />
          <Route path="map"         element={<TreeMapPage />} />
          <Route path="scan"        element={<ScanQR />} />
          <Route path="public"      element={<PublicPortal />} />
          <Route path="ai-identify" element={<AIIdentify />} />
          <Route path="community"   element={<CommunityStructure />} />
          <Route path="upgrade"     element={<Upgrade />} />
          <Route path="unknown-species" element={<UnknownSpeciesReview />} />
          <Route path="reports"     element={<ReportsAndTools />} />

          {/* Admin-only (backend enforces, frontend just shows/hides nav) */}
          <Route path="qr-manager"  element={<QRManager />} />
          <Route path="health-logs" element={<HealthLogs />} />
          <Route path="admin/users" element={<AdminUsers />} />
        </Route>

        {/* ── 404 ── */}
        <Route path="*" element={<PageNotFound />} />
      </Routes>
    </BrowserRouter>
  );
}
