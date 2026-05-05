import api from "./client";

export const storageApi = {
  uploadPhoto: async (file) => {
    const form = new FormData();
    form.append("file", file);
    const { data } = await api.post("/storage/upload-photo", form, {
      headers: { "Content-Type": "multipart/form-data" },
    });
    return data; // { file_url, path }
  },

  uploadQR: async (blob) => {
    const form = new FormData();
    form.append("file", blob, "qr.png");
    const { data } = await api.post("/storage/upload-qr", form, {
      headers: { "Content-Type": "multipart/form-data" },
    });
    return data;
  },

  deletePhoto: async (path) => {
    await api.delete("/storage/delete-photo", { params: { path } });
  },
};
