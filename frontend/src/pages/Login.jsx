import { useState } from "react";
import { useNavigate, Link } from "react-router-dom";
import { useAuth } from "@/lib/AuthContext";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Leaf, Loader2, ArrowRight } from "lucide-react";
import { toast } from "sonner";

export default function Login() {
  const { login } = useAuth();
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    try {
      await login(email, password);
      navigate("/dashboard");
    } catch (err) {
      toast.error(err?.response?.data?.detail || "Invalid email or password");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-[#07130c] relative flex items-center justify-center px-4 overflow-hidden text-white">
      {/* Ambient background glows */}
      <div className="absolute top-[-20%] left-[-10%] w-[600px] h-[600px] rounded-full bg-emerald-900/15 blur-[130px] pointer-events-none" />
      <div className="absolute bottom-[-20%] right-[-10%] w-[600px] h-[600px] rounded-full bg-primary/10 blur-[130px] pointer-events-none" />

      {/* Floating Leaves */}
      <div className="absolute top-1/4 left-1/12 text-emerald-600/10 pointer-events-none animate-bounce" style={{ animationDuration: "8s" }}>
        <Leaf className="w-12 h-12 rotate-[15deg]" />
      </div>
      <div className="absolute bottom-1/4 right-1/12 text-primary/10 pointer-events-none animate-bounce" style={{ animationDuration: "10s" }}>
        <Leaf className="w-16 h-16 rotate-[-45deg]" />
      </div>

      <div className="w-full max-w-md relative z-10">
        {/* Logo */}
        <div className="flex items-center gap-3 mb-8 justify-center">
          <div className="w-11 h-11 bg-primary rounded-xl flex items-center justify-center shadow-lg shadow-primary/20 border border-primary/20">
            <Leaf className="w-6 h-6 text-primary-foreground animate-pulse" />
          </div>
          <div>
            <h1 className="font-fraunces text-3xl font-semibold text-emerald-400 leading-none">
              TreeTrace
            </h1>
            <p className="text-muted-foreground text-xs mt-1 uppercase tracking-wider">Geo-Spatial Inventory</p>
          </div>
        </div>

        {/* Card */}
        <div className="bg-[#0b1f13]/80 border border-white/5 backdrop-blur-2xl rounded-2xl p-8 shadow-2xl transition-all duration-300 hover:shadow-emerald-950/40 hover:border-emerald-500/20">
          <h2 className="font-fraunces text-2xl font-semibold tracking-wide text-white mb-1.5">Sign in</h2>
          <p className="text-muted-foreground/80 text-sm mb-6">
            Enter your credentials to access the dashboard
          </p>

          <form onSubmit={handleSubmit} className="space-y-5">
            <div className="space-y-2">
              <Label htmlFor="email" className="text-gray-300 text-xs font-semibold uppercase tracking-wider">Email Address</Label>
              <Input
                id="email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="you@example.com"
                required
                autoComplete="email"
                className="bg-black/30 border-white/10 text-white placeholder:text-muted-foreground/40 focus:border-primary/50 focus-visible:ring-primary/20 h-10 px-3"
              />
            </div>
            <div className="space-y-2">
              <div className="flex justify-between items-center">
                <Label htmlFor="password" className="text-gray-300 text-xs font-semibold uppercase tracking-wider">Password</Label>
              </div>
              <Input
                id="password"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••"
                required
                autoComplete="current-password"
                className="bg-black/30 border-white/10 text-white placeholder:text-muted-foreground/40 focus:border-primary/50 focus-visible:ring-primary/20 h-10 px-3"
              />
            </div>

            <Button type="submit" className="w-full flex items-center justify-center gap-2 h-11 bg-primary hover:bg-primary/90 text-primary-foreground font-semibold rounded-xl shadow-lg shadow-primary/20 mt-6" disabled={loading}>
              {loading ? (
                <Loader2 className="w-5 h-5 animate-spin" />
              ) : (
                <>
                  Sign in
                  <ArrowRight className="w-4 h-4" />
                </>
              )}
            </Button>
          </form>
        </div>

        <p className="text-center text-sm text-muted-foreground/80 mt-6">
          Don&apos;t have an account?{" "}
          <Link to="/register" className="text-emerald-400 hover:text-emerald-300 font-medium transition-colors hover:underline">
            Create one
          </Link>
        </p>
      </div>
    </div>
  );
}
