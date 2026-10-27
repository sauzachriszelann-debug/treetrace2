import "@testing-library/jest-dom/vitest";
import "fake-indexeddb/auto";
import { IDBFactory } from "fake-indexeddb";
import { Blob as NodeBlob } from "node:buffer";
import { beforeEach, vi } from "vitest";

// jsdom's Blob class is not recognized by Node's structuredClone, so photo
// Blobs would be degraded into plain objects inside IndexedDB. Use Node's
// native Blob (same API surface) so cloning behaves like a real browser.
globalThis.Blob = NodeBlob;
if (typeof window !== "undefined") window.Blob = NodeBlob;

// jsdom does not implement these; the offline UI and store rely on them.
if (typeof globalThis.structuredClone === "undefined") {
  globalThis.structuredClone = (value) => {
    if (typeof Blob !== "undefined" && value instanceof Blob) return value;
    return JSON.parse(JSON.stringify(value));
  };
}

if (typeof URL.createObjectURL !== "function") {
  URL.createObjectURL = vi.fn(() => `blob:mock-${Math.random()}`);
  URL.revokeObjectURL = vi.fn();
}

if (typeof window.matchMedia !== "function") {
  window.matchMedia = () => ({
    matches: false,
    media: "",
    addEventListener: () => {},
    removeEventListener: () => {},
    addListener: () => {},
    removeListener: () => {},
    onchange: null,
    dispatchEvent: () => false,
  });
}

// Some runtimes expose an inert plain-object `localStorage` (no Web Storage
// methods). Guarantee working Storage implementations before any test runs.
function memoryStorage() {
  const map = new Map();
  return {
    getItem: (key) => (map.has(String(key)) ? map.get(String(key)) : null),
    setItem: (key, value) => {
      map.set(String(key), String(value));
    },
    removeItem: (key) => {
      map.delete(String(key));
    },
    clear: () => map.clear(),
    key: (index) => [...map.keys()][index] ?? null,
    get length() {
      return map.size;
    },
  };
}

function ensureStorage(name) {
  let storage;
  try {
    storage = globalThis[name];
  } catch {
    storage = null;
  }
  if (!storage || typeof storage.setItem !== "function" || typeof storage.clear !== "function") {
    storage = memoryStorage();
    globalThis[name] = storage;
    if (typeof window !== "undefined") {
      try {
        window[name] = storage;
      } catch {
        /* window property may be getter-only */
      }
    }
  }
  return storage;
}

ensureStorage("localStorage");
ensureStorage("sessionStorage");

// Fresh storage for every test: no IndexedDB residue, no leftover drafts or
// legacy queue keys between cases.
beforeEach(() => {
  globalThis.indexedDB = new IDBFactory();
  localStorage.clear();
  sessionStorage.clear();
  vi.restoreAllMocks();
  vi.clearAllMocks();
});
