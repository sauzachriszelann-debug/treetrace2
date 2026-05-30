import { useState, useEffect, useCallback } from "react";
import { treesApi } from "@/api/trees";
import { healthLogsApi } from "@/api/healthLogs";
import { toast } from "sonner";

const QUEUE_KEY = "treetrace_offline_queue";

export function useOfflineSync() {
  const [isOnline, setIsOnline]   = useState(navigator.onLine);
  const [queue, setQueue]         = useState(() => {
    try {
      return JSON.parse(localStorage.getItem(QUEUE_KEY) || "[]");
    } catch {
      return [];
    }
  });
  const [syncing, setSyncing]     = useState(false);

  // Track online/offline
  useEffect(() => {
    const goOnline  = () => { setIsOnline(true);  toast.success("Back online. Review Field Sync before uploading."); };
    const goOffline = () => { setIsOnline(false); toast.warning("You are offline. Saved changes will wait for review."); };
    window.addEventListener("online",  goOnline);
    window.addEventListener("offline", goOffline);
    return () => {
      window.removeEventListener("online",  goOnline);
      window.removeEventListener("offline", goOffline);
    };
  }, []);

  // Persist queue to localStorage
  useEffect(() => {
    localStorage.setItem(QUEUE_KEY, JSON.stringify(queue));
  }, [queue]);

  const addToQueue = useCallback((action) => {
    const entry = {
      id:        Date.now(),
      timestamp: new Date().toISOString(),
      verified: false,
      ...action,
    };
    setQueue((q) => [...q, entry]);
    toast.info("Saved offline. Review it in Field Sync before uploading.");
    return entry;
  }, []);

  const syncQueue = useCallback(async () => {
    if (syncing || queue.length === 0) return;
    setSyncing(true);
    let succeeded = 0;
    let failed    = 0;
    const remaining = [];

    for (const item of queue) {
      if (!item.verified) {
        remaining.push(item);
        continue;
      }
      try {
        if (item.type === "CREATE_TREE") {
          await treesApi.create(item.payload);
        } else if (item.type === "UPDATE_TREE") {
          await treesApi.update(item.treeId, item.payload);
        } else if (item.type === "CREATE_HEALTH_LOG") {
          await healthLogsApi.create(item.payload);
        } else if (item.type === "CREATE_PLANTING_RECOMMENDATION") {
          const { plantingApi } = await import("@/api/planting");
          await plantingApi.create(item.payload);
        }
        succeeded++;
      } catch {
        failed++;
        remaining.push(item);
      }
    }

    setQueue(remaining);
    setSyncing(false);

    if (succeeded > 0) toast.success(`Synced ${succeeded} verified offline record${succeeded > 1 ? "s" : ""}!`);
    if (failed    > 0) toast.error(`${failed} record${failed > 1 ? "s" : ""} failed to sync.`);
  }, [queue, syncing]);

  const setVerified = useCallback((id, verified) => {
    setQueue((q) => q.map((item) => item.id === id ? { ...item, verified } : item));
  }, []);

  const verifyAll = useCallback(() => {
    setQueue((q) => q.map((item) => ({ ...item, verified: true })));
  }, []);

  const removeFromQueue = useCallback((id) => {
    setQueue((q) => q.filter((item) => item.id !== id));
  }, []);

  const clearQueue = useCallback(() => {
    setQueue([]);
    localStorage.removeItem(QUEUE_KEY);
  }, []);

  return {
    isOnline,
    queue,
    queueLength: queue.length,
    syncing,
    addToQueue,
    syncQueue,
    setVerified,
    verifyAll,
    removeFromQueue,
    clearQueue,
  };
}
