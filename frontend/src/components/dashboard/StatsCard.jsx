import { Card, CardContent } from "@/components/ui/card";
import { cn } from "@/lib/utils";

export default function StatsCard({ title, value, subtitle, icon: Icon, color = "primary", onClick }) {
    const colors = {
        primary: "bg-primary/10 text-primary",
        emerald: "bg-emerald-100 text-emerald-700",
        amber: "bg-amber-100 text-amber-700",
        red: "bg-red-100 text-red-700",
        blue: "bg-blue-100 text-blue-700",
    };

    return (
        <Card
            role={onClick ? "button" : undefined}
            tabIndex={onClick ? 0 : undefined}
            onClick={onClick}
            onKeyDown={(event) => {
                if (onClick && (event.key === "Enter" || event.key === " ")) {
                    event.preventDefault();
                    onClick();
                }
            }}
            className={cn(
                "border-border hover:shadow-md transition-shadow",
                onClick && "cursor-pointer"
            )}
        >
            <CardContent className="p-4 sm:p-6">
                <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0 flex-1">
                        <p className="text-muted-foreground text-sm font-medium">{title}</p>
                        <p className="font-fraunces text-2xl font-semibold text-foreground mt-1 sm:text-3xl">{value}</p>
                        {subtitle && <p className="text-muted-foreground text-xs mt-1">{subtitle}</p>}
                    </div>
                    {Icon && (
                        <div className={cn("rounded-xl p-2.5 sm:p-3", colors[color])}>
                            <Icon className="w-5 h-5" />
                        </div>
                    )}
                </div>
            </CardContent>
        </Card>
    );
}
