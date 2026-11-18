import api from './client';

export const trainingDataApi = {
  list: async (params = {}) => (await api.get('/admin/training-data', { params })).data,
  manifest: async () => (await api.get('/admin/training-data/manifest.csv', { responseType: 'blob' })).data,
  exportPhotos: async (ids) => {
    const response = await api.post('/admin/training-data/export', { ids }, { responseType: 'blob', timeout: 240000 });
    return { blob: response.data, count: Number(response.headers['x-exported-images']),
      failed: Number(response.headers['x-export-failures']) };
  },
};
