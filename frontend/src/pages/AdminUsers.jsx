import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { usersApi } from "@/api/users";
import { useAuth } from "@/lib/AuthContext";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select, SelectContent, SelectItem,
  SelectTrigger, SelectValue,
} from "@/components/ui/select";
import {
  Dialog, DialogContent, DialogHeader,
  DialogTitle, DialogTrigger,
} from "@/components/ui/dialog";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import {
  UserPlus, Users, ShieldCheck, UserX, UserCheck,
  Loader2, Eye, EyeOff, Copy, CheckCircle2, KeyRound,
} from "lucide-react";
import { toast } from "sonner";

export default function AdminUsers() {
  const { user: me } = useAuth();
  const qc           = useQueryClient();

  const [open, setOpen]         = useState(false);
  const [showPass, setShowPass] = useState(false);
  const [saving, setSaving]     = useState(false);
  const [created, setCreated]   = useState(null);   // holds { ...user, temp_password }
  const [copied, setCopied]     = useState(false);

  const [form, setForm] = useState({
    full_name: "",
    email:     "",
    role:      "field_worker",
    password:  "",            // empty = auto-generate
  });

  const { data: users = [], isLoading } = useQuery({
    queryKey: ["users"],
    queryFn:  usersApi.list,
    retry:    false,
    enabled:  me?.role === "admin" || me?.role === "UserRole.admin",
  });

  // Non-admin guard
  const roleStr = String(me?.role ?? "").toLowerCase();
  if (me && !roleStr.includes("admin")) {
    return (
      <div className="p-8 flex items-center justify-center h-96">
        <div className="text-center text-muted-foreground">
          <Users className="w-12 h-12 mx-auto mb-3 opacity-30" />
          <p className="font-medium text-foreground">Access Restricted</p>
          <p className="text-sm mt-1">You need admin privileges to view this page.</p>
        </div>
      </div>
    );
  }

  const setF = (k, v) => setForm((f) => ({ ...f, [k]: v }));

  const resetForm = () => {
    setForm({ full_name: "", email: "", role: "field_worker", password: "" });
    setShowPass(false);
    setCreated(null);
    setCopied(false);
  };

  const handleCreate = async (e) => {
    e.preventDefault();
    if (!form.email) return;
    if (form.password && form.password.length < 6) {
      toast.error("Password must be at least 6 characters.");
      return;
    }
    setSaving(true);
    try {
      const result = await usersApi.create({
        full_name: form.full_name,
        email:     form.email,
        role:      form.role,
        password:  form.password || undefined,
      });
      qc.invalidateQueries({ queryKey: ["users"] });
      setCreated(result);          // show success panel with temp password
    } catch (err) {
      toast.error(err?.response?.data?.detail || "Failed to create user.");
    } finally {
      setSaving(false);
    }
  };

  const copyPassword = () => {
    if (!created?.temp_password) return;
    navigator.clipboard.writeText(created.temp_password);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const handleRoleChange = async (userId, role) => {
    try {
      await usersApi.updateRole(userId, role);
      qc.invalidateQueries({ queryKey: ["users"] });
      toast.success("Role updated.");
    } catch {
      toast.error("Failed to update role.");
    }
  };

  const handlePlanChange = async (userId, plan) => {
    try {
      await usersApi.updateSubscription(userId, plan);
      qc.invalidateQueries({ queryKey: ["users"] });
      toast.success(plan === "pro" ? "User upgraded to Pro." : "User moved to Free plan.");
    } catch {
      toast.error("Failed to update subscription.");
    }
  };

  const handleDeactivate = async (userId) => {
    if (!confirm("Deactivate this user? They will no longer be able to log in.")) return;
    try {
      await usersApi.deactivate(userId);
      qc.invalidateQueries({ queryKey: ["users"] });
      toast.success("User deactivated.");
    } catch {
      toast.error("Failed to deactivate user.");
    }
  };

  const handleActivate = async (userId) => {
    try {
      await usersApi.activate(userId);
      qc.invalidateQueries({ queryKey: ["users"] });
      toast.success("User reactivated.");
    } catch {
      toast.error("Failed to activate user.");
    }
  };

  const activeCount   = users.filter((u) => u.is_active).length;
  const adminCount    = users.filter((u) => String(u.role).includes("admin")).length;
  const upgradeCount  = users.filter((u) => u.upgrade_requested).length;

  return (
    <div className="p-8 max-w-4xl mx-auto">
      {/* Header */}
      <div className="flex items-start justify-between mb-6">
        <div>
          <h1 className="font-fraunces text-3xl font-semibold">User Management</h1>
          <p className="text-muted-foreground mt-1">
            {activeCount} active · {adminCount} admin{adminCount !== 1 ? "s" : ""} · {upgradeCount} upgrade request{upgradeCount !== 1 ? "s" : ""}
          </p>
        </div>

        <Dialog open={open} onOpenChange={(v) => { setOpen(v); if (!v) resetForm(); }}>
          <DialogTrigger asChild>
            <Button className="flex items-center gap-2">
              <UserPlus className="w-4 h-4" />
              Add User
            </Button>
          </DialogTrigger>

          <DialogContent className="max-w-md">
            <DialogHeader>
              <DialogTitle className="font-fraunces text-xl">Add New User</DialogTitle>
            </DialogHeader>

            {/* ── Success panel shown after creation ── */}
            {created ? (
              <div className="space-y-4 mt-2">
                <div className="flex items-center gap-3 p-4 bg-emerald-50 border border-emerald-200 rounded-xl">
                  <CheckCircle2 className="w-8 h-8 text-emerald-500 flex-shrink-0" />
                  <div>
                    <p className="font-semibold text-emerald-800">Account created!</p>
                    <p className="text-sm text-emerald-700">{created.full_name} · {created.email}</p>
                  </div>
                </div>

                {/* Temp password panel — only shown if password was auto-generated */}
                {created.temp_password ? (
                  <div className="space-y-2">
                    <div className="flex items-center gap-2">
                      <KeyRound className="w-4 h-4 text-amber-500" />
                      <Label className="text-amber-700 font-medium">Temporary Password</Label>
                    </div>
                    <div className="flex items-center gap-2">
                      <code className="flex-1 font-mono text-sm bg-amber-50 border border-amber-200 rounded-lg px-3 py-2 text-amber-900 select-all">
                        {created.temp_password}
                      </code>
                      <Button
                        size="icon"
                        variant="outline"
                        onClick={copyPassword}
                        className="flex-shrink-0"
                      >
                        {copied
                          ? <CheckCircle2 className="w-4 h-4 text-emerald-500" />
                          : <Copy className="w-4 h-4" />}
                      </Button>
                    </div>
                    <p className="text-xs text-amber-700 bg-amber-50 border border-amber-100 rounded-lg p-2">
                      ⚠️ A welcome email with these credentials has been sent to <strong>{created.email}</strong> (if email is configured). Copy and keep this password — it won't be shown again.
                    </p>
                  </div>
                ) : (
                  <p className="text-sm text-muted-foreground bg-muted p-3 rounded-lg">
                    The password you set has been saved. Share it with the user directly.
                  </p>
                )}

                <div className="flex gap-2">
                  <Button
                    className="flex-1"
                    onClick={() => { resetForm(); setOpen(false); }}
                  >
                    Done
                  </Button>
                  <Button
                    variant="outline"
                    className="flex-1"
                    onClick={resetForm}
                  >
                    Add Another
                  </Button>
                </div>
              </div>
            ) : (
              /* ── Create form ── */
              <form onSubmit={handleCreate} className="space-y-4 mt-2">
                <div className="space-y-1.5">
                  <Label>Full Name</Label>
                  <Input
                    value={form.full_name}
                    onChange={(e) => setF("full_name", e.target.value)}
                    placeholder="Juan dela Cruz"
                    autoFocus
                  />
                </div>

                <div className="space-y-1.5">
                  <Label>Email <span className="text-destructive">*</span></Label>
                  <Input
                    type="email"
                    value={form.email}
                    onChange={(e) => setF("email", e.target.value)}
                    placeholder="user@example.com"
                    required
                  />
                </div>

                <div className="space-y-1.5">
                  <Label>Role</Label>
                  <Select value={form.role} onValueChange={(v) => setF("role", v)}>
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="field_worker">
                        <span className="flex items-center gap-2">
                          <span className="w-2 h-2 rounded-full bg-blue-500 inline-block" />
                          Field Worker
                        </span>
                      </SelectItem>
                      <SelectItem value="admin">
                        <span className="flex items-center gap-2">
                          <span className="w-2 h-2 rounded-full bg-amber-500 inline-block" />
                          Admin
                        </span>
                      </SelectItem>
                    </SelectContent>
                  </Select>
                </div>

                <div className="space-y-1.5">
                  <Label className="flex items-center justify-between">
                    Password
                    <span className="text-xs text-muted-foreground font-normal">
                      Leave blank to auto-generate
                    </span>
                  </Label>
                  <div className="relative">
                    <Input
                      type={showPass ? "text" : "password"}
                      value={form.password}
                      onChange={(e) => setF("password", e.target.value)}
                      placeholder="Min 6 characters (optional)"
                      className="pr-10"
                    />
                    <button
                      type="button"
                      onClick={() => setShowPass((p) => !p)}
                      className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
                    >
                      {showPass ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                    </button>
                  </div>
                  {!form.password && (
                    <p className="text-xs text-muted-foreground">
                      A random password will be generated and shown to you after creation.
                    </p>
                  )}
                </div>

                <Button type="submit" className="w-full" disabled={saving}>
                  {saving && <Loader2 className="w-4 h-4 animate-spin mr-2" />}
                  {saving ? "Creating…" : "Create Account"}
                </Button>
              </form>
            )}
          </DialogContent>
        </Dialog>
      </div>

      {/* User list */}
      {isLoading ? (
        <div className="space-y-3">
          {[1, 2, 3].map((i) => (
            <div key={i} className="h-20 bg-muted rounded-xl animate-pulse" />
          ))}
        </div>
      ) : users.length === 0 ? (
        <div className="text-center py-16 text-muted-foreground">
          <Users className="w-12 h-12 mx-auto mb-3 opacity-20" />
          <p>No users yet. Click "Add User" to create the first account.</p>
        </div>
      ) : (
        <div className="space-y-2">
          {users.map((u) => {
            const isAdmin = String(u.role).includes("admin");
            const isInstitutional = String(u.role).includes("admin") || String(u.role).includes("field_worker");
            const planLabel = isInstitutional ? "INSTITUTIONAL" : (u.subscription_plan || "free").toUpperCase();
            return (
              <Card key={u.id} className={`border-border ${!u.is_active ? "opacity-60" : ""}`}>
                <CardContent className="p-4">
                  <div className="flex items-center justify-between flex-wrap gap-3">
                    {/* Avatar + info */}
                    <div className="flex items-center gap-3">
                      <div className={`w-10 h-10 rounded-full flex items-center justify-center flex-shrink-0 ${
                        isAdmin ? "bg-amber-100" : "bg-primary/10"
                      }`}>
                        <span className={`font-semibold text-sm ${isAdmin ? "text-amber-700" : "text-primary"}`}>
                          {u.full_name?.charAt(0)?.toUpperCase() || u.email?.charAt(0)?.toUpperCase() || "U"}
                        </span>
                      </div>
                      <div>
                        <div className="flex items-center gap-2 flex-wrap">
                          <p className="font-medium text-sm">{u.full_name || "—"}</p>
                          {u.id === me?.id && (
                            <Badge variant="outline" className="text-xs px-1.5 py-0">You</Badge>
                          )}
                          {!u.is_active && (
                            <Badge variant="destructive" className="text-xs px-1.5 py-0">Inactive</Badge>
                          )}
                          <Badge variant={u.subscription_plan === "pro" || isInstitutional ? "default" : "outline"} className="text-xs px-1.5 py-0">
                            {planLabel}
                          </Badge>
                          {u.upgrade_requested && (
                            <Badge className="text-xs px-1.5 py-0 bg-emerald-600">Upgrade requested</Badge>
                          )}
                        </div>
                        <p className="text-muted-foreground text-xs">{u.email}</p>
                        <p className="text-muted-foreground text-xs">
                          AI today: {u.ai_identifications_today ?? 0}{u.subscription_plan === "pro" || isInstitutional ? " · unlimited" : " / 3 free"}
                        </p>
                      </div>
                    </div>

                    {/* Controls */}
                    <div className="flex items-center gap-2">
                      {u.id !== me?.id && u.is_active ? (
                        <>
                          <Select
                            value={String(u.role).split(".").pop()}
                            onValueChange={(v) => handleRoleChange(u.id, v)}
                          >
                            <SelectTrigger className="w-36 h-8 text-xs">
                              <SelectValue />
                            </SelectTrigger>
                            <SelectContent>
                              <SelectItem value="field_worker">Field Worker</SelectItem>
                              <SelectItem value="admin">Admin</SelectItem>
                            </SelectContent>
                          </Select>
                          <Select
                            value={u.subscription_plan || "free"}
                            onValueChange={(v) => handlePlanChange(u.id, v)}
                          >
                            <SelectTrigger className="w-28 h-8 text-xs">
                              <SelectValue />
                            </SelectTrigger>
                            <SelectContent>
                              <SelectItem value="free">Free</SelectItem>
                              <SelectItem value="pro">Pro</SelectItem>
                            </SelectContent>
                          </Select>
                        </>
                      ) : (
                        <div className="flex items-center gap-1.5 px-3 py-1.5 rounded-md bg-muted text-xs text-muted-foreground">
                          <ShieldCheck className="w-3.5 h-3.5" />
                          {String(u.role).split(".").pop()?.replace("_", " ")}
                        </div>
                      )}

                      {u.id !== me?.id && (
                        u.is_active ? (
                          <Button
                            variant="ghost"
                            size="icon"
                            className="w-8 h-8 text-muted-foreground hover:text-destructive"
                            title="Deactivate user"
                            onClick={() => handleDeactivate(u.id)}
                          >
                            <UserX className="w-4 h-4" />
                          </Button>
                        ) : (
                          <Button
                            variant="ghost"
                            size="icon"
                            className="w-8 h-8 text-muted-foreground hover:text-emerald-600"
                            title="Reactivate user"
                            onClick={() => handleActivate(u.id)}
                          >
                            <UserCheck className="w-4 h-4" />
                          </Button>
                        )
                      )}
                    </div>
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
}
