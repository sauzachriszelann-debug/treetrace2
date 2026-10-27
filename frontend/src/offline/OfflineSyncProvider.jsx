// G7 (D3/D7): one app-wide offline sync provider.
//
// A SINGLE service instance backs every consumer (Sidebar badge, Field
// Sync page, producers) so concurrent hook instances can never clobber each
// other's queue state - the data-loss bug in the old localStorage hook.
//
// D7: cross-tab coordination uses the Web Locks API where supported. If the
// browser lacks it, AUTOMATIC synchronization is disabled with an explained
// banner and a manual "Sync Verified" path remains available (in-tab
// single-flight only). G7 never claims exactly-once delivery for
// non-idempotent operations.

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
} from "react";
import { toast } from "sonner";
import { QueueStore } from "./store.js";
import { OfflineQueueService } from "./service.js";
import { treesApi } from "@/api/trees";
import { healthLogsApi } from "@/api/healthLogs";
import { treeSubmissionsApi } from "@/api/treeSubmissions";
import { aiApi } from "@/api/ai";
import { plantingApi } from "@/api/planting";
import { storageApi } from "@/api/storage";

/// Marks requests issued by background sync so the shared axios interceptor
/// keeps the queue and shows a session banner instead of hard-redirecting
/// (G7 D4).
export const SYNC_CONFIG = { offlineSync: true };

export async function dispatchQueueItem(type, payload) {
  switch (type) {
    case "CREATE_TREE":
      return treesApi.create(payload, SYNC_CONFIG);
    case "CREATE_TREE_SUBMISSION":
      return treeSubmissionsApi.create(payload, SYNC_CONFIG);
    case "CREATE_HEALTH_LOG":
      return healthLogsApi.create(payload, SYNC_CONFIG);
    case "SUBMIT_UNKNOWN":
      return aiApi.submitUnknown(payload, SYNC_CONFIG);
    case "CREATE_PLANTING_RECOMMENDATION":
      return plantingApi.create(payload, SYNC_CONFIG);
    default:
      throw new Error(`Unknown offline queue type: ${type}`);
  }
}

export async function uploadQueuedPhoto(blob, purpose) {
  const data = await storageApi.uploadPhoto(blob, purpose, SYNC_CONFIG);
  return data?.file_url ?? null;
}

export const OfflineSyncContext = createContext(null);

const hasSession = () => {
  try {
    return Boolean(localStorage.getItem("treetrace_token"));
  } catch {
    return false;
  }
};

export const locksSupported = () =>
  typeof navigator !== "undefined" && Boolean(navigator.locks?.request);

export function OfflineSyncProvider({ children }) {
  const storeRef = useRef(null);
  const serviceRef = useRef(null);
  const [ready, setReady] = useState(false);
  const [queue, setQueue] = useState([]);
  const [notice, setNotice] = useState(null);
  const [result, setResult] = useState(null);
  const [isOnline, setIsOnline] = useState(
    typeof navigator !== "undefined" ? navigator.onLine : true,
  );
  const [syncing, setSyncing] = useState(false);
  const [autoSyncAvailable, setAutoSyncAvailable] = useState(true);

  const refresh = useCallback(async () => {
    const service = serviceRef.current;
    if (!service) return;
    setQueue(await service.all());
    setNotice(storeRef.current?.notice ?? null);
  }, []);

  useEffect(() => {
    let cancelled = false;

    (async () => {
      const store = new QueueStore();
      const service = new OfflineQueueService({
        store,
        isOnline: async () => navigator.onLine,
        sender: dispatchQueueItem,
        uploader: uploadQueuedPhoto,
      });
      try {
        await service.load();
      } catch (error) {
        console.warn("Offline queue failed to initialize:", error);
      }
      if (cancelled) return;
      storeRef.current = store;
      serviceRef.current = service;
      setAutoSyncAvailable(locksSupported());
      setQueue(await service.all());
      setNotice(store.notice);
      setReady(true);
    })();

    const onOnline = () => {
      setIsOnline(true);
      // D3: reconnect triggers automatic sync of PREVIOUSLY VERIFIED items
      // only; the service enforces that rule itself.
      if (!locksSupported()) return; // D7: auto disabled without cross-tab lock
      if (!hasSession()) return; // no session: stay quiet, keep the queue
      (async () => {
        const service = serviceRef.current;
        if (!service) return;
        try {
          const run = async () => service.sync({ auto: true });
          const res = locksSupported()
            ? await navigator.locks.request("treetrace_offline_sync", run)
            : await run();
          if (res?.ran) {
            setResult(res);
            await refresh();
          }
        } catch (error) {
          // Auto-sync must never break the app; the queue stays intact.
          console.warn("Auto-sync failed:", error);
        }
      })();
    };
    const onOffline = () => setIsOnline(false);

    window.addEventListener("online", onOnline);
    window.addEventListener("offline", onOffline);
    return () => {
      cancelled = true;
      window.removeEventListener("online", onOnline);
      window.removeEventListener("offline", onOffline);
    };
  }, [refresh]);

  const syncNow = useCallback(
    async ({ auto = false } = {}) => {
      const service = serviceRef.current;
      if (!service || service.syncInFlight) return null;
      setSyncing(true);
      try {
        const run = async () => service.sync({ auto });
        const res =
          locksSupported() && !auto
            ? await navigator.locks.request("treetrace_offline_sync", run)
            : await run();
        setResult(res);
        if (res?.ran) {
          if (res.synced > 0) {
            toast.success(
              `Synced ${res.synced} verified offline record${res.synced === 1 ? "" : "s"}!`,
            );
          }
          if (res.authError) {
            toast.error("Session expired. Sign in again to resume sync.");
          } else if (res.heldForReview > 0) {
            toast.warning(
              `${res.heldForReview} record${res.heldForReview === 1 ? "" : "s"} held for your review - never retried automatically.`,
            );
          } else if (res.keptForRetry > 0) {
            toast.error(
              `${res.keptForRetry} record${res.keptForRetry === 1 ? "" : "s"} failed to sync. Will retry with backoff.`,
            );
          }
        }
        return res;
      } catch (error) {
        console.warn("Sync run failed:", error);
        return null;
      } finally {
        setSyncing(false);
        await refresh();
      }
    },
    [refresh],
  );

  const enqueue = useCallback(
    async (type, payload, options = {}) => {
      const service = serviceRef.current;
      if (!service) throw new Error("offline queue not ready");
      const item = await service.enqueue(type, payload, options);
      await refresh();
      return item;
    },
    [refresh],
  );

  const setVerified = useCallback(
    async (itemId, verified) => {
      await serviceRef.current?.setVerified(itemId, verified);
      await refresh();
    },
    [refresh],
  );

  const verifyAll = useCallback(async () => {
    await serviceRef.current?.verifyAll();
    await refresh();
  }, [refresh]);

  const remove = useCallback(
    async (itemId) => {
      await serviceRef.current?.remove(itemId);
      await refresh();
    },
    [refresh],
  );

  const retryOnce = useCallback(
    async (itemId) => {
      await serviceRef.current?.resolveForManualRetry(itemId);
      await refresh();
      await syncNow({ auto: false });
    },
    [refresh, syncNow],
  );

  const continueWithoutPhoto = useCallback(
    async (itemId) => {
      await serviceRef.current?.continueWithoutPhoto(itemId);
      await refresh();
    },
    [refresh],
  );

  const dismissNotice = useCallback(async () => {
    await storeRef.current?.clearNotice();
    setNotice(null);
  }, []);

  const getPhoto = useCallback(async (itemId) => {
    try {
      return await storeRef.current?.getPhoto(itemId);
    } catch {
      return null;
    }
  }, []);

  const value = {
    ready,
    isOnline,
    queue,
    queueLength: queue.length,
    syncing,
    result,
    notice,
    autoSyncAvailable,
    enqueue,
    setVerified,
    verifyAll,
    remove,
    retryOnce,
    continueWithoutPhoto,
    syncNow,
    refresh,
    dismissNotice,
    getPhoto,
    setResult,
  };

  return (
    <OfflineSyncContext.Provider value={value}>
      {children}
    </OfflineSyncContext.Provider>
  );
}

export function useOfflineSyncStore() {
  const context = useContext(OfflineSyncContext);
  if (!context) {
    throw new Error("useOfflineSyncStore must be used within OfflineSyncProvider");
  }
  return context;
}
