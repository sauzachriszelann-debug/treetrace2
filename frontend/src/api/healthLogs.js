import api from "./client";

export const healthLogsApi = {
  list: async (params = {}) => {
    const { data } = await api.get("/health-logs/", { params });
    return data;
  },

  listByTree: async (treeId) => {
    const { data } = await api.get("/health-logs/", { params: { tree_id: treeId } });
    return data;
  },

  create: async (payload) => {
    const { data } = await api.post("/health-logs/", payload);
    return data;
  },

  delete: async (id) => {
    await api.delete(`/health-logs/${id}`);
  },
};
