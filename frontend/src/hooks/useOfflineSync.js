// G7: this hook is now a thin view over the app-wide OfflineSyncProvider.
// The previous implementation kept a per-instance localStorage copy of the
// queue, so two mounted components could overwrite each other's state and
// silently lose records (safeguard 7). There is now ONE queue instance.

import { useOfflineSyncStore } from "@/offline/OfflineSyncProvider";

export function useOfflineSync() {
  const {
    isOnline,
    queue,
    queueLength,
    syncing,
    result,
    enqueue,
    syncNow,
    setVerified,
    verifyAll,
    remove,
  } = useOfflineSyncStore();

  return {
    isOnline,
    queue,
    queueLength,
    syncing,
    result,
    addToQueue: enqueue,
    syncQueue: () => syncNow({ auto: false }),
    setVerified,
    verifyAll,
    removeFromQueue: remove,
  };
}
