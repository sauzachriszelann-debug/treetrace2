import api from "./client";

export const plantingApi = {
  list: async (params = {}) => {
    const { data } = await api.get("/planting/", { params });
    return data;
  },

  suggestions: async (params = {}) => {
    const { data } = await api.get("/planting/suggestions", { params });
    return data;
  },

  create: async (payload) => {
    const { data } = await api.post("/planting/", payload);
    return data;
  },

  update: async (id, payload) => {
    const { data } = await api.patch(`/planting/${id}`, payload);
    return data;
  },
};
