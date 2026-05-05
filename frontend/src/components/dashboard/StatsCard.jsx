import { Card, CardContent } from "@/components/ui/card";
import { cn } from "@/lib/utils";

export default function StatsCard({ title, value, subtitle, icon: Icon, color = "primary" }) {
    const colors = {
        primary: "bg-primary/10 text-primary",
        emerald: "bg-emerald-100 text-emerald-700",
        amber: "bg-amber-100 text-amber-700",
        red: "bg-red-100 text-red-700",
        blue: "bg-blue-100 text-blue-700",
    };

    return (
        <Card className="border-border hover:shadow-md transition-shadow">
            <CardContent className="p-6">
                <div className="flex items-start justify-between">
                    <div className="flex-1">
                        <p className="text-muted-foreground text-sm font-medium">{title}</p>
                        <p className="font-fraunces text-3xl font-semibold text-foreground mt-1">{value}</p>
                        {subtitle && <p className="text-muted-foreground text-xs mt-1">{subtitle}</p>}
                    </div>
                    {Icon && (
                        <div className={cn("p-3 rounded-xl", colors[color])}>
                            <Icon className="w-5 h-5" />
                        </div>
                    )}
                </div>
            </CardContent>
        </Card>
    );
}