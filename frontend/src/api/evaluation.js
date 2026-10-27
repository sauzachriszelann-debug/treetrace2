import api from "./client";

// G5: official evaluation results exist only as validated artifacts on the
// backend. The API is read-only for runs - there is no create/mutate call.
export const evaluationApi = {
  results: async () => {
    const { data } = await api.get("/evaluation/results");
    return data;
  },

  listRuns: async () => {
    const { data } = await api.get("/evaluation/runs");
    return data;
  },

  getRun: async (runId) => {
    const { data } = await api.get(`/evaluation/runs/${runId}`);
    return data;
  },

  // Field rows: staff-only, unverified provenance, never official metrics.
  listFieldRows: async () => {
    const { data } = await api.get("/evaluation/rows");
    return data;
  },

  importFieldCsv: async (replace = true) => {
    const { data } = await api.post("/evaluation/import-csv", null, {
      params: { replace },
    });
    return data;
  },
};
