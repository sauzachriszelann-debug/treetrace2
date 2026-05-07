import { useState } from "react";
import {
  Building2, CheckCircle2, Crown, FileDown, Leaf, Loader2,
  Map, PieChart, Sparkles, Sprout, Users,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { usersApi } from "@/api/users";
import { useAuth } from "@/lib/AuthContext";
import { toast } from "sonner";

const plans = [
  {
    name: "Starter",
    price: "Free",
    suffix: "/ month",
    badge: "Citizens",
    icon: Sprout,
    tone: "border-emerald-200",
    features: ["Up to 10 trees", "3 AI identifications per day", "Public map, QR, and basic profiles"],
    note: "Ideal for citizens and community contributors.",
  },
  {
    name: "Professional",
    price: "₱99",
    suffix: "/ month",
    badge: "Most Popular",
    icon: Crown,
    featured: true,
    features: ["Unlimited AI identification", "Full dashboard and analytics", "Reports, health history, and priority review"],
    note: "For researchers, schools, NGOs, and active field teams.",
  },
  {
    name: "Enterprise",
    price: "₱399+",
    suffix: "/ month",
    badge: "LGU / Institution",
    icon: Building2,
    dark: true,
    features: ["Unlimited trees and users", "Barangay/LGU reporting", "Training, onboarding, and compliance support"],
    note: "For city-wide and institutional deployments.",
  },
];

export default function Upgrade() {
  const { user, checkUserAuth } = useAuth();
  const [saving, setSaving] = useState(false);
  const role = String(user?.role || "").toLowerCase();
  const isInstitutional = role.includes("admin") || role.includes("field_worker");
  const isPro = user?.subscription_plan === "pro";
  const requested = user?.upgrade_requested;
  const planLabel = isInstitutional ? "INSTITUTIONAL ACCESS" : `${(user?.subscription_plan || "free").toUpperCase()} PLAN`;

  const requestUpgrade = async () => {
    setSaving(true);
    try {
      await usersApi.requestUpgrade();
      await checkUserAuth();
      toast.success("Upgrade request submitted for admin approval.");
    } catch (error) {
      toast.error(error?.response?.data?.detail || "Could not submit upgrade request.");
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="p-8 max-w-6xl mx-auto space-y-7">
      <div className="flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
        <div>
          <h1 className="font-fraunces text-3xl font-semibold text-foreground">
            Revenue Streams & Pricing
          </h1>
          <p className="text-muted-foreground mt-1 max-w-2xl">
            Freemium SaaS access for public users, with paid Pro and institutional plans for advanced conservation work.
          </p>
        </div>
        <Badge variant={isPro || isInstitutional ? "default" : "outline"} className="w-fit px-3 py-1">
          Current plan: {planLabel}
        </Badge>
      </div>

      <section className="space-y-3">
        <div className="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-primary">
          <Leaf className="w-4 h-4" />
          SaaS Subscription Plans - Core Revenue
        </div>
        <div className="grid gap-4 lg:grid-cols-3">
          {plans.map((plan) => (
            <PlanCard key={plan.name} plan={plan} />
          ))}
        </div>
      </section>

      <section className="space-y-3">
        <div className="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-primary">
          <PieChart className="w-4 h-4" />
          Additional Revenue Streams
        </div>
        <div className="grid gap-4 md:grid-cols-3">
          <RevenueCard icon={<Users className="w-5 h-5" />} title="Training & Onboarding" text="Paid setup sessions for LGUs, schools, barangays, and field teams." />
          <RevenueCard icon={<FileDown className="w-5 h-5" />} title="Reports & Compliance" text="Paid exports for tree permits, carbon stock, biodiversity summaries, and LGU reporting." />
          <RevenueCard icon={<Map className="w-5 h-5" />} title="GIS Data Packages" text="Institutional access to curated map layers and tree inventory analytics." />
        </div>
      </section>

      <Card className="border-primary/20 bg-primary/5">
        <CardContent className="p-5 flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
          <div>
            <p className="font-semibold">
              {isInstitutional ? "Your account has institutional access." : isPro ? "Your account is already Pro." : requested ? "Upgrade request pending." : "Request Professional access"}
            </p>
            <p className="text-sm text-muted-foreground mt-1">
              This prototype uses admin-approved payment verification. GCash, Maya, or PayMongo can be connected in deployment.
            </p>
          </div>
          <Button onClick={requestUpgrade} disabled={saving || isPro || requested || isInstitutional} className="w-full md:w-auto">
            {saving && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
            {isInstitutional ? "Institutional Active" : isPro ? "Pro Active" : requested ? "Waiting for Admin" : "Request Upgrade"}
          </Button>
        </CardContent>
      </Card>
    </div>
  );
}

function PlanCard({ plan }) {
  const Icon = plan.icon;
  return (
    <Card className={[
      "border h-full",
      plan.featured ? "bg-primary text-primary-foreground border-primary shadow-md" : "",
      plan.dark ? "bg-slate-900 text-white border-slate-700" : "",
      !plan.featured && !plan.dark ? plan.tone : "",
    ].join(" ")}>
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
          <Badge variant={plan.featured || plan.dark ? "secondary" : "outline"}>{plan.badge}</Badge>
          <Icon className="w-5 h-5 opacity-80" />
        </div>
        <CardTitle className="pt-3">
          <span className="text-3xl font-bold">{plan.price}</span>
          <span className="text-sm font-normal opacity-75 ml-2">{plan.suffix}</span>
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="space-y-2 text-sm">
          {plan.features.map((feature) => (
            <Feature key={feature} text={feature} />
          ))}
        </div>
        <p className="text-xs opacity-75 italic">{plan.note}</p>
      </CardContent>
    </Card>
  );
}

function Feature({ text }) {
  return (
    <div className="flex items-start gap-2">
      <CheckCircle2 className="w-4 h-4 mt-0.5 flex-shrink-0" />
      <span>{text}</span>
    </div>
  );
}

function RevenueCard({ icon, title, text }) {
  return (
    <Card className="border-border">
      <CardContent className="p-4 flex gap-3">
        <div className="w-10 h-10 rounded-lg bg-primary/10 text-primary flex items-center justify-center flex-shrink-0">
          {icon}
        </div>
        <div>
          <p className="font-semibold">{title}</p>
          <p className="text-sm text-muted-foreground mt-1">{text}</p>
        </div>
      </CardContent>
    </Card>
  );
}
