import api from "./client";
import { preparePredictionPhoto } from "@/lib/predictionPhoto";

export const aiApi = {
  predictGallerySize: async (file, { treetopFile, signal } = {}) => {
    const form = new FormData();
    form.append('file', await preparePredictionPhoto(file));
    if (treetopFile) form.append('treetop_file', await preparePredictionPhoto(treetopFile));
    const { data } = await api.post('/ai/gallery-size-prediction', form, {
      headers: { 'Content-Type': 'multipart/form-data' }, timeout: 120000, signal,
    });
    return data;
  },

  estimateAge: async (payload, { signal } = {}) => {
    const { data } = await api.post('/ai/estimate-age', payload, { signal, timeout: 60000 });
    return data;
  },

  identifyFromFile: async (file) => {
    const form = new FormData();
    form.append("file", await preparePredictionPhoto(file));
    const { data } = await api.post("/ai/identify", form, {
      headers: { "Content-Type": "multipart/form-data" },
    });
    return data;
  },

  measureDbh: async (
    file,
    {
      referenceHint = "No reference object provided. Estimate using visible surroundings only.",
      method = "Camera-assisted photo measurement",
      knownDistanceM = null,
    } = {}
  ) => {
    const form = new FormData();
    form.append("file", file);
    form.append("reference_hint", referenceHint);
    form.append("method", method);
    if (knownDistanceM) {
      form.append("known_distance_m", String(knownDistanceM));
    }
    const { data } = await api.post("/ai/measure-dbh-file", form, {
      headers: { "Content-Type": "multipart/form-data" },
    });
    return data;
  },

  identifyFromUrl: async (image_url) => {
    const { data } = await api.post("/ai/identify-url", { image_url });
    return data;
  },

  communityStructure: async () => {
    const { data } = await api.get("/ai/community-structure");
    return data;
  },

  listEndangered: async () => {
    const { data } = await api.get("/ai/endangered");
    return data;
  },

  submitUnknown: async (payload, config) => {
    const { data } = await api.post("/ai/unknown-species", payload, config);
    return data;
  },

  listUnknown: async () => {
    const { data } = await api.get("/ai/unknown-species");
    return data;
  },

  reviewUnknown: async (id, payload) => {
    const { data } = await api.put(`/ai/unknown-species/${id}/review`, payload);
    return data;
  },
};
