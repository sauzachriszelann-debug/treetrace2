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

  speciesPhotos: async () => {
    const { data } = await api.get("/planting/species-photos");
    return data;
  },

  saveSpeciesPhoto: async (payload) => {
    const { data } = await api.put("/planting/species-photos", payload);
    return data;
  },

  create: async (payload, config) => {
    const { data } = await api.post("/planting/", payload, config);
    return data;
  },

  update: async (id, payload) => {
    const { data } = await api.patch(`/planting/${id}`, payload);
    return data;
  },
};
