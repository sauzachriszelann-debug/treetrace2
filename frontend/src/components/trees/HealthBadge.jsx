import { cn } from "@/lib/utils";

const config = {
    "Not assessed": { bg: "bg-slate-100 text-slate-700 border-slate-200", dot: "bg-slate-400" },
    Healthy: { bg: "bg-emerald-100 text-emerald-800 border-emerald-200", dot: "bg-emerald-500" },
    Fair: { bg: "bg-amber-100 text-amber-800 border-amber-200", dot: "bg-amber-500" },
    Poor: { bg: "bg-red-100 text-red-800 border-red-200", dot: "bg-red-500" },
};

export default function HealthBadge({ status, className }) {
    const c = config[status] || config["Not assessed"];
    return (
        <span className={cn("inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium border", c.bg, className)}>
            <span className={cn("w-1.5 h-1.5 rounded-full", c.dot)} />
            {status || "Not assessed"}
        </span>
    );
}