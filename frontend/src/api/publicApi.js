import axios from "axios";

// Separate instance — no auth header needed
const publicApi = axios.create({
  baseURL: "/api/public",
  headers: { "Content-Type": "application/json" },
});

export const publicApiService = {
  getTree: async (id) => {
    const { data } = await publicApi.get(`/tree/${id}`);
    return data;
  },

  getTreeHealthLogs: async (id) => {
    const { data } = await publicApi.get(`/tree/${id}/health-logs`);
    return data;
  },

  listTrees: async () => {
    const { data } = await publicApi.get("/trees");
    return data;
  },

  // Returns ALL trees (including those without GPS) for list view + stats
  listAllTrees: async () => {
    const { data } = await publicApi.get("/trees/all");
    return data;
  },
};
