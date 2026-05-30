import { useOfflineSync } from "@/hooks/useOfflineSync";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Checkbox } from "@/components/ui/checkbox";
import { CloudUpload, Trash2 } from "lucide-react";

export default function FieldSync() {
  const { queue, syncing, setVerified, verifyAll, removeFromQueue, syncQueue } = useOfflineSync();
  const verified = queue.filter((item) => item.verified).length;

  return (
    <div className="p-4 sm:p-6 lg:p-8">
      <div className="mb-6 flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h1 className="font-fraunces text-2xl font-semibold sm:text-3xl">Field Sync Review</h1>
          <p className="mt-1 text-muted-foreground">Review offline web records before uploading them to the server.</p>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={verifyAll} disabled={queue.length === 0}>Verify All</Button>
          <Button onClick={syncQueue} disabled={verified === 0 || syncing}>
            <CloudUpload className="mr-2 h-4 w-4" />
            {syncing ? "Syncing" : "Sync Verified"}
          </Button>
        </div>
      </div>

      <Card className="mb-5">
        <CardContent className="flex flex-wrap items-center gap-3 p-4">
          <Badge variant="outline">{queue.length} pending</Badge>
          <Badge>{verified} verified</Badge>
          <p className="text-sm text-muted-foreground">Only verified items will sync.</p>
        </CardContent>
      </Card>

      {queue.length === 0 ? (
        <Card>
          <CardContent className="p-10 text-center text-muted-foreground">No offline records waiting for review.</CardContent>
        </Card>
      ) : (
        <div className="grid gap-4 lg:grid-cols-2">
          {queue.map((item) => (
            <Card key={item.id} className={item.verified ? "border-emerald-300" : ""}>
              <CardHeader className="flex flex-row items-start justify-between gap-3">
                <div>
                  <CardTitle className="text-base">{titleFor(item)}</CardTitle>
                  <p className="text-xs text-muted-foreground">{labelFor(item.type)} · {new Date(item.timestamp).toLocaleString()}</p>
                </div>
                <Checkbox checked={item.verified} onCheckedChange={(checked) => setVerified(item.id, Boolean(checked))} />
              </CardHeader>
              <CardContent className="space-y-3">
                <div className="rounded-lg border bg-muted/30 p-3 text-sm">
                  {Object.entries(item.payload || {}).slice(0, 6).map(([key, value]) => (
                    <div key={key} className="grid grid-cols-[130px_1fr] gap-2 py-1">
                      <span className="font-medium text-muted-foreground">{prettyKey(key)}</span>
                      <span className="truncate">{String(value ?? "")}</span>
                    </div>
                  ))}
                </div>
                <div className="flex items-center justify-between">
                  <span className={item.verified ? "text-sm font-medium text-emerald-600" : "text-sm font-medium text-amber-600"}>
                    {item.verified ? "Verified for sync" : "Needs verification"}
                  </span>
                  <Button variant="ghost" className="text-destructive hover:text-destructive" onClick={() => removeFromQueue(item.id)}>
                    <Trash2 className="mr-2 h-4 w-4" /> Remove
                  </Button>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}

function titleFor(item) {
  const payload = item.payload || {};
  return payload.common_name || payload.species_name || payload.scientific_name || "Offline record";
}

function labelFor(type) {
  if (type === "CREATE_TREE") return "Tree inventory";
  if (type === "UPDATE_TREE") return "Tree update";
  if (type === "CREATE_HEALTH_LOG") return "Health log";
  if (type === "CREATE_PLANTING_RECOMMENDATION") return "Planting suggestion";
  return "Offline record";
}

function prettyKey(key) {
  return key.replaceAll("_", " ").replace(/\b\w/g, (match) => match.toUpperCase());
}
