import { beforeEach, expect, test, vi } from 'vitest';
import api from '../client';
import { aiApi } from '../ai';
import { preparePredictionPhoto } from '@/lib/predictionPhoto';
vi.mock('../client', () => ({ default: { post: vi.fn() } }));
beforeEach(() => api.post.mockReset().mockResolvedValue({ data: { status: 'predicted' } }));

test('gallery upload sends both bounded files to the authenticated client endpoint', async () => {
  const file = new File(['original'], 'original.jpg', { type: 'image/jpeg' });
  const top = new File(['top'], 'top.png', { type: 'image/png' });
  await aiApi.predictGallerySize(file, { treetopFile: top });
  const [path, form, options] = api.post.mock.calls[0];
  expect(path).toBe('/ai/gallery-size-prediction');
  expect(form.get('file').name).toBe('original.jpg');
  expect(form.get('treetop_file').name).toBe('top.png');
  expect(options.timeout).toBe(120000);
});

test('unsupported formats do not trigger a provider upload', async () => {
  await expect(aiApi.predictGallerySize(new File(['bad'], 'bad.txt', { type: 'text/plain' }))).rejects.toThrow('JPEG');
  expect(api.post).not.toHaveBeenCalled();
});

test('age contract uses backend field names and keeps AI provenance', async () => {
  const input = { scientific_name: 'Gmelina arborea', dbh_cm: 45, height_m: 11, dimensions_source: 'ai_prediction' };
  await aiApi.estimateAge(input);
  expect(api.post).toHaveBeenCalledWith('/ai/estimate-age', input, expect.objectContaining({ timeout: 60000 }));
});

test('large AI images are resized without replacing the original file', async () => {
  const original = new File([new Uint8Array(1_900_000)], 'large.jpg', { type: 'image/jpeg' });
  const close = vi.fn();
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, 'createImageBitmap');
  Object.defineProperty(globalThis, 'createImageBitmap', { configurable: true,
    value: vi.fn().mockResolvedValue({ width: 4000, height: 3000, close }) });
  const create = document.createElement.bind(document);
  const drawImage = vi.fn();
  vi.spyOn(document, 'createElement').mockImplementation(tag => tag === 'canvas'
    ? { getContext: () => ({ drawImage }), toBlob: callback => callback(new Blob(['compressed'], { type: 'image/jpeg' })) }
    : create(tag));
  try {
    const derivative = await preparePredictionPhoto(original);
    expect(derivative.size).toBeLessThan(1_800_000);
    expect(derivative.type).toBe('image/jpeg');
    expect(original.size).toBe(1_900_000);
    expect(drawImage).toHaveBeenCalledWith(expect.any(Object), 0, 0, 1600, 1200);
    expect(close).toHaveBeenCalledOnce();
  } finally {
    if (descriptor) Object.defineProperty(globalThis, 'createImageBitmap', descriptor);
    else delete globalThis.createImageBitmap;
  }
});
