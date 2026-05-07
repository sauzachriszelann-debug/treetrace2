import api from "./client";

export const usersApi = {
  list: async () => {
    const { data } = await api.get("/users");
    return data;
  },

  // Creates user — returns { ...user, temp_password } if password was auto-generated
  create: async ({ full_name, email, role, password }) => {
    const { data } = await api.post("/users", { full_name, email, role, password });
    return data;
  },

  // Kept for backwards compat
  invite: async (email, role, full_name = "") => {
    const { data } = await api.post("/users", { email, role, full_name });
    return data;
  },

  updateRole: async (userId, role) => {
    const { data } = await api.put(`/users/${userId}/role`, null, { params: { role } });
    return data;
  },

  updateSubscription: async (userId, plan) => {
    const { data } = await api.put(`/users/${userId}/subscription`, null, { params: { plan } });
    return data;
  },

  requestUpgrade: async () => {
    const { data } = await api.post("/users/request-upgrade");
    return data;
  },

  deactivate: async (userId) => {
    const { data } = await api.put(`/users/${userId}/deactivate`);
    return data;
  },

  activate: async (userId) => {
    const { data } = await api.put(`/users/${userId}/activate`);
    return data;
  },
};
