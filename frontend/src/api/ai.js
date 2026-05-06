import api from "./client";

export const aiApi = {
  identifyFromFile: async (file) => {
    const form = new FormData();
    form.append("file", file);
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

  submitUnknown: async (payload) => {
    const { data } = await api.post("/ai/unknown-species", payload);
    return data;
  },

  listUnknown: async () => {
    const { data } = await api.get("/ai/unknown-species");
    return data;
  },
};
