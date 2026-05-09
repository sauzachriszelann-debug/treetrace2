import api from "./client";

export const treesApi = {
  list: async (params = {}) => {
    const { data } = await api.get("/trees/", { params });
    return data;
  },

  get: async (id) => {
    const { data } = await api.get(`/trees/${id}`);
    return data;
  },

  create: async (payload) => {
    const { data } = await api.post("/trees/", payload);
    return data;
  },

  update: async (id, payload) => {
    const { data } = await api.patch(`/trees/${id}`, payload);
    return data;
  },

  delete: async (id) => {
    await api.delete(`/trees/${id}`);
  },

  stats: async () => {
    const { data } = await api.get("/trees/stats/summary");
    return data;
  },

  qrPrint: async () => {
    const { data } = await api.get("/trees/qr-print");
    return data;
  },

  routePlan: async (params = {}) => {
    const { data } = await api.get("/trees/route-plan", { params });
    return data;
  },

  exportInventoryCsv: async () => {
    const { data } = await api.get("/trees/reports/inventory.csv", {
      responseType: "blob",
    });
    return data;
  },
};
