import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { MemoryRouter } from 'react-router-dom';
import { aiApi } from '@/api/ai';
import { storageApi } from '@/api/storage';
import GalleryTreePredictions from './GalleryTreePredictions';
import TreeForm from './TreeForm';

vi.mock('@/api/ai', () => ({ aiApi: { predictGallerySize: vi.fn(), estimateAge: vi.fn(), identifyFromFile: vi.fn() } }));
vi.mock('@/api/storage', () => ({ storageApi: { uploadPhoto: vi.fn() } }));
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() } }));

const original = new File(['image'], 'tree.jpg', { type: 'image/jpeg' });
const top = new File(['top'], 'top.jpg', { type: 'image/jpeg' });
const size = {
  status: 'predicted', method: 'gallery_yolo_vision_prediction', quality: 'unvalidated',
  prediction_basis: 'visual_appearance', validated_accuracy: false, trunk_detected: true,
  target_source: 'yolo', target_identified: true, predicted_dbh_cm: 45,
  predicted_height_m: null, needs_treetop_photo: true, height_reason_code: 'top_hidden',
  reason: 'Unvalidated prediction.', preview_png: 'test-overlay',
};
const age = { status: 'estimated', estimation_basis: 'published_growth', dbh_age_years: 17.6,
  height_age_years: null, source: { citation: 'Published study', context: 'Plantation trial',
    url: 'https://doi.org/10.1007/s11056-023-10013-x' }, reason: 'Experimental estimate.' };

beforeEach(() => {
  let counter = 0;
  vi.spyOn(URL, 'createObjectURL').mockImplementation(() => `blob:test-${++counter}`);
  vi.spyOn(URL, 'revokeObjectURL').mockImplementation(() => {});
  aiApi.predictGallerySize.mockReset().mockResolvedValue(size);
  aiApi.estimateAge.mockReset().mockResolvedValue(age);
  aiApi.identifyFromFile.mockReset().mockResolvedValue({ common_name: 'Yemane', scientific_name: 'Gmelina arborea',
    estimated_dbh_cm: 99, estimated_height_m: 50 });
  storageApi.uploadPhoto.mockResolvedValue({ file_url: 'https://example.test/tree.jpg' });
});
afterEach(cleanup);

test('shows trunk prediction and one sourced age without measured controls', async () => {
  render(<GalleryTreePredictions file={original} scientificName="Gmelina arborea" />);
  expect(await screen.findByText('About 18 years (estimated)')).toBeInTheDocument();
  expect(screen.getByText('Published growth data')).toBeInTheDocument();
  expect(screen.getByRole('button', { name: 'Expand Trunk detection' })).toBeInTheDocument();
  expect(screen.getByLabelText('Treetop photo')).toBeInTheDocument();
  expect(aiApi.estimateAge).toHaveBeenCalledWith(expect.objectContaining({
    dbh_cm: 45, height_m: null, dimensions_source: 'ai_prediction' }), expect.any(Object));
  fireEvent.click(screen.getByRole('button', { name: 'Expand Original tree photo' }));
  expect(screen.getByRole('dialog')).toBeInTheDocument();
});

test('treetop upload updates height and age check while preserving original DBH', async () => {
  aiApi.predictGallerySize.mockResolvedValueOnce(size).mockResolvedValueOnce({ ...size,
    predicted_dbh_cm: 99, predicted_height_m: 11, treetop_photo_used: true, needs_treetop_photo: false });
  render(<GalleryTreePredictions file={original} scientificName="Gmelina arborea" />);
  const picker = await screen.findByLabelText('Treetop photo');
  fireEvent.change(picker, { target: { files: [top] } });
  expect(await screen.findByText('Height estimated using your original photo and added treetop photo.')).toBeInTheDocument();
  expect(screen.getByText('DBH (cm):').textContent).toContain('45');
  expect(screen.getByText('Height (m):').textContent).toContain('11');
  expect(aiApi.predictGallerySize).toHaveBeenLastCalledWith(original, expect.objectContaining({ treetopFile: top }));
  await waitFor(() => expect(aiApi.estimateAge).toHaveBeenLastCalledWith(expect.objectContaining({ dbh_cm: 45, height_m: 11 }), expect.any(Object)));
});

test('a failed treetop match leaves height unavailable and offers replacement', async () => {
  aiApi.predictGallerySize.mockResolvedValueOnce(size).mockResolvedValueOnce({ ...size,
    height_reason: 'Treetop does not match the original tree.', treetop_photo_used: false });
  render(<GalleryTreePredictions file={original} scientificName="" />);
  fireEvent.change(await screen.findByLabelText('Treetop photo'), { target: { files: [top] } });
  expect(await screen.findByRole('alert')).toHaveTextContent('does not match');
  expect(screen.getByText('Height (m):').textContent).toContain('Unavailable');
  expect(screen.getByLabelText('Treetop photo')).not.toBeDisabled();
});

test('old photo response cannot replace a newer photo prediction', async () => {
  let finish;
  aiApi.predictGallerySize.mockReturnValueOnce(new Promise(resolve => { finish = resolve; }))
    .mockResolvedValueOnce({ ...size, predicted_dbh_cm: 20 });
  const { rerender } = render(<GalleryTreePredictions file={original} scientificName="" />);
  await waitFor(() => expect(aiApi.predictGallerySize).toHaveBeenCalledTimes(1));
  rerender(<GalleryTreePredictions file={top} scientificName="" />);
  await waitFor(() => expect(screen.getByText('DBH (cm):').textContent).toContain('20'));
  await act(async () => finish(size));
  expect(screen.getByText('DBH (cm):').textContent).toContain('20');
});

test('AI sizes fill form fields and are saved with explicit provenance', async () => {
  const submit = vi.fn();
  const { container } = render(<MemoryRouter><TreeForm onSubmit={submit} /></MemoryRouter>);
  fireEvent.change(screen.getByLabelText('Tree photo'), { target: { files: [original] } });
  expect(await screen.findByText('About 18 years (estimated)')).toBeInTheDocument();
  expect(screen.getByLabelText('DBH (cm)')).toHaveValue(45);
  expect(screen.getByLabelText('Height (m)')).toHaveValue(null);
  fireEvent.submit(container.querySelector('form'));
  await waitFor(() => expect(submit).toHaveBeenCalled());
  const [payload] = submit.mock.calls[0];
  expect(payload.dbh_cm).toBe(45);
  expect(payload.notes).toContain('AI-estimated DBH');
  for (const key of ['height_m', 'carbon_kg', 'biomass_kg', 'age_estimate']) expect(payload).not.toHaveProperty(key);
  expect(payload.scientific_name).toBe('Gmelina arborea');
  expect(screen.queryByText('Manual DBH Calculator')).not.toBeInTheDocument();
  expect(screen.queryByText('Advanced photo measurement tools')).not.toBeInTheDocument();
});

test('added top fills height while manual changes to DBH survive', async () => {
  aiApi.predictGallerySize.mockResolvedValueOnce(size).mockResolvedValueOnce({ ...size,
    predicted_dbh_cm: 99, predicted_height_m: 15, treetop_photo_used: true, needs_treetop_photo: false });
  render(<MemoryRouter><TreeForm onSubmit={vi.fn()} /></MemoryRouter>);
  fireEvent.change(screen.getByLabelText('Tree photo'), { target: { files: [original] } });
  await waitFor(() => expect(screen.getByLabelText('DBH (cm)')).toHaveValue(45));
  fireEvent.change(screen.getByLabelText('DBH (cm)'), { target: { value: '42' } });
  fireEvent.change(screen.getByLabelText('Treetop photo'), { target: { files: [top] } });
  await waitFor(() => expect(screen.getByLabelText('Height (m)')).toHaveValue(15));
  expect(screen.getByLabelText('DBH (cm)')).toHaveValue(42);
  await waitFor(() => expect(aiApi.estimateAge).toHaveBeenLastCalledWith(
    expect.objectContaining({ dbh_cm: 42, height_m: 15 }), expect.any(Object)));
});

test('replacing a photo clears previous AI values but never reuses its height', async () => {
  aiApi.predictGallerySize.mockResolvedValueOnce({ ...size, predicted_height_m: 15 })
    .mockResolvedValueOnce({ ...size, predicted_dbh_cm: 20, predicted_height_m: null });
  render(<MemoryRouter><TreeForm onSubmit={vi.fn()} /></MemoryRouter>);
  fireEvent.change(screen.getByLabelText('Tree photo'), { target: { files: [original] } });
  await waitFor(() => expect(screen.getByLabelText('Height (m)')).toHaveValue(15));
  fireEvent.change(screen.getByLabelText('Tree photo'), { target: { files: [top] } });
  await waitFor(() => expect(screen.getByLabelText('DBH (cm)')).toHaveValue(20));
  expect(screen.getByLabelText('Height (m)')).toHaveValue(null);
});

test('photo predictions preserve existing manual measurements', async () => {
  render(<MemoryRouter><TreeForm initial={{ dbh_cm: 30, height_m: 12 }} onSubmit={vi.fn()} /></MemoryRouter>);
  fireEvent.change(screen.getByLabelText('Tree photo'), { target: { files: [original] } });
  await screen.findByText('About 18 years (estimated)');
  expect(screen.getByLabelText('DBH (cm)')).toHaveValue(30);
  expect(screen.getByLabelText('Height (m)')).toHaveValue(12);
});

test('old identification cannot replace species after selecting another photo', async () => {
  let finish;
  aiApi.identifyFromFile.mockReturnValueOnce(new Promise(resolve => { finish = resolve; }))
    .mockResolvedValueOnce({ common_name: 'Mango', scientific_name: 'Mangifera indica' });
  render(<MemoryRouter><TreeForm onSubmit={vi.fn()} /></MemoryRouter>);
  fireEvent.change(screen.getByLabelText('Tree photo'), { target: { files: [original] } });
  await waitFor(() => expect(aiApi.identifyFromFile).toHaveBeenCalledTimes(1));
  fireEvent.change(screen.getByLabelText('Tree photo'), { target: { files: [top] } });
  await waitFor(() => expect(screen.getByLabelText('Common Name *')).toHaveValue('Mango'));
  await act(async () => finish({ common_name: 'Yemane', scientific_name: 'Gmelina arborea' }));
  expect(screen.getByLabelText('Common Name *')).toHaveValue('Mango');
});
