import { cn } from "@/lib/utils";

const config = {
    Healthy: { bg: "bg-emerald-100 text-emerald-800 border-emerald-200", dot: "bg-emerald-500" },
    Fair: { bg: "bg-amber-100 text-amber-800 border-amber-200", dot: "bg-amber-500" },
    Poor: { bg: "bg-red-100 text-red-800 border-red-200", dot: "bg-red-500" },
};

export default function HealthBadge({ status, className }) {
    const c = config[status] || config.Fair;
    return (
        <span className={cn("inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium border", c.bg, className)}>
            <span className={cn("w-1.5 h-1.5 rounded-full", c.dot)} />
            {status || "Unknown"}
        </span>
    );
}