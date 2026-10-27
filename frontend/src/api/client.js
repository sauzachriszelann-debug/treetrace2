import axios from "axios";

const api = axios.create({
  baseURL: "/api",
  headers: { "Content-Type": "application/json" },
});

// Attach JWT from localStorage to every request
api.interceptors.request.use((config) => {
  const token = localStorage.getItem("treetrace_token");
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// Handle auth errors
api.interceptors.response.use(
  (res) => res,
  (error) => {
    const status = error.response?.status;
    if (error.response && typeof error.response.data !== "object") {
      error.response.data = {
        detail:
          status >= 500
            ? "The TreeTrace server is temporarily unavailable. Please try again later."
            : "The request could not be completed. Please try again.",
      };
    }
    if (status === 401) {
      // G7 D4: a background sync request (offlineSync) keeps the queue and
      // must not yank the user out of the app mid-run - the sync UI shows a
      // session-expired banner instead. The dead token is still removed
      // (security behavior unchanged); redirects stay for every other call.
      const isBackgroundSync = Boolean(error.config?.offlineSync);
      localStorage.removeItem("treetrace_token");
      if (!isBackgroundSync) {
        window.location.href = "/login";
      }
    }
    // 403 Forbidden — don't redirect to login, let the component handle it
    return Promise.reject(error);
  }
);

export default api;
