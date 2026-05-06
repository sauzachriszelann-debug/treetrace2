import api from "./client";

export const authApi = {
  login: async (email, password) => {
    const { data } = await api.post("/auth/login", { email, password });
    return data; // { access_token, token_type }
  },

  register: async (full_name, email, password, role = "citizen") => {
    const { data } = await api.post("/auth/register", {
      full_name,
      email,
      password,
      role,
    });
    return data;
  },

  me: async () => {
    const { data } = await api.get("/auth/me");
    return data;
  },
};
