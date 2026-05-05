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
    if (status === 401) {
      // Only redirect if token is actually missing/invalid (not just a permission error)
      const token = localStorage.getItem("treetrace_token");
      if (!token) {
        window.location.href = "/login";
      } else {
        // Token expired — clear and redirect
        localStorage.removeItem("treetrace_token");
        window.location.href = "/login";
      }
    }
    // 403 Forbidden — don't redirect to login, let the component handle it
    return Promise.reject(error);
  }
);

export default api;
