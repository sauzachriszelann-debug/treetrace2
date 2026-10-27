import api from "./client";

export const treeSubmissionsApi = {
  create: async (payload, config) => {
    const { data } = await api.post("/tree-submissions/", payload, config);
    return data;
  },

  list: async (status) => {
    const { data } = await api.get("/tree-submissions/", {
      params: status && status !== "all" ? { status } : {},
    });
    return data;
  },

  my: async () => {
    const { data } = await api.get("/tree-submissions/my");
    return data;
  },

  approve: async (id, overrides = {}) => {
    const { data } = await api.post(`/tree-submissions/${id}/approve`, overrides);
    return data;
  },

  reject: async (id, reason) => {
    const { data } = await api.post(`/tree-submissions/${id}/reject`, { reason });
    return data;
  },

  link: async (id, treeId) => {
    const { data } = await api.post(`/tree-submissions/${id}/link`, {
      tree_id: treeId,
    });
    return data;
  },

  reopen: async (id) => {
    const { data } = await api.post(`/tree-submissions/${id}/reopen`);
    return data;
  },

  // Path B integration: convert an IDENTIFIED unknown-species entry into a
  // pending tree submission (staff only; replay-safe server-side).
  convertUnknownSpecies: async (entryId) => {
    const { data } = await api.post(`/ai/unknown-species/${entryId}/convert`);
    return data;
  },
};
