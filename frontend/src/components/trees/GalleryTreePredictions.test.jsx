import { act, cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { MemoryRouter } from 'react-router-dom';
import { aiApi } from '@/api/ai';
import { storageApi } from '@/api/storage';
import GalleryTreePredictions from './GalleryTreePredictions';
import TreeForm from './TreeForm';

vi.mock('@/api/ai', () => ({ aiApi: { predictGallerySize: vi.fn(), estimateAge: vi.fn(), identifyFromFile: vi.fn(), submitUnknown: vi.fn() } }));
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

test('missing base and top can be uploaded separately for the same original photo', async () => {
  const base = new File(['base'], 'base.jpg', { type: 'image/jpeg' });
  aiApi.predictGallerySize.mockResolvedValueOnce({
    ...size, status: 'cannot_estimate', predicted_dbh_cm: null, dbh_reason_code: 'base_hidden',
  }).mockResolvedValueOnce({
    ...size, treebase_photo_used: true,
  }).mockResolvedValueOnce({
    ...size, treebase_photo_used: true, treetop_photo_used: true, predicted_height_m: 11,
  });
  render(<GalleryTreePredictions file={original} scientificName="" />);
  fireEvent.change(await screen.findByLabelText('Tree base photo'), { target: { files: [base] } });
  expect(aiApi.predictGallerySize).toHaveBeenCalledTimes(1);
  fireEvent.click(screen.getByRole('button', { name: 'Cancel' }));
  expect(aiApi.predictGallerySize).toHaveBeenCalledTimes(1);
  fireEvent.change(screen.getByLabelText('Tree base photo'), { target: { files: [base] } });
  fireEvent.click(screen.getByRole('button', { name: 'Yes, analyze photos' }));
  expect(await screen.findByText('45')).toBeInTheDocument();
  fireEvent.change(screen.getByLabelText('Treetop photo'), { target: { files: [top] } });
  fireEvent.click(screen.getByRole('button', { name: 'Yes, analyze photos' }));
  expect(await screen.findByText('11')).toBeInTheDocument();
  expect(aiApi.predictGallerySize).toHaveBeenLastCalledWith(
    original, expect.objectContaining({ treebaseFile: base, treetopFile: top }),
  );
});

test('treetop upload updates height and age check while preserving original DBH', async () => {
  aiApi.predictGallerySize.mockResolvedValueOnce(size).mockResolvedValueOnce({ ...size,
    predicted_dbh_cm: 99, predicted_height_m: 11, treetop_photo_used: true, needs_treetop_photo: false });
  render(<GalleryTreePredictions file={original} scientificName="Gmelina arborea" />);
  const picker = await screen.findByLabelText('Treetop photo');
  fireEvent.change(picker, { target: { files: [top] } });
  fireEvent.click(screen.getByRole('button', { name: 'Yes, analyze photos' }));
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
  fireEvent.click(screen.getByRole('button', { name: 'Yes, analyze photos' }));
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
  fireEvent.click(screen.getByRole('button', { name: 'Yes, analyze photos' }));
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

test('a photo below the confidence cutoff goes to unknown species review', async () => {
  let finishAnalysis;
  aiApi.predictGallerySize.mockReturnValueOnce(new Promise(resolve => { finishAnalysis = resolve; }));
  aiApi.identifyFromFile.mockResolvedValueOnce({
    not_identified: true,
    source: 'local_efficientnet_b0_trial',
    confidence_percent: 74.99,
    below_confidence_threshold: true,
    suggested_species: {
      common_name: 'Narra', scientific_name: 'Pterocarpus indicus', confidence_percent: 74.99,
    },
  });
  aiApi.submitUnknown.mockResolvedValueOnce({ id: 42 });
  const saveRecord = vi.fn();
  render(<MemoryRouter><TreeForm onSubmit={saveRecord} /></MemoryRouter>);
  fireEvent.change(screen.getByLabelText('Tree photo'), { target: { files: [original] } });

  const dialog = await screen.findByRole('dialog', { name: 'Species needs expert review' });
  expect(within(dialog).getByRole('img', { name: 'Tree photo for expert review' })).toHaveAttribute('src', expect.stringMatching(/^blob:/));
  expect(within(dialog).getByLabelText('Suggested common name')).toHaveValue('Narra');
  expect(within(dialog).getByLabelText('Suggested scientific name')).toHaveValue('Pterocarpus indicus');
  expect(within(dialog).getByLabelText('AI confidence')).toHaveValue('74.99%');
  fireEvent.click(within(dialog).getByRole('button', { name: 'Expand Original tree photo' }));
  const photoDialog = await screen.findByRole('dialog', { name: 'Original tree photo' });
  expect(within(photoDialog).getByRole('img', { name: 'Tree photo for expert review' })).toBeInTheDocument();
  fireEvent.click(within(photoDialog).getByRole('button', { name: 'Close' }));
  expect(screen.queryByRole('dialog', { name: 'Original tree photo' })).toBeNull();
  expect(within(dialog).getByRole('button', { name: 'Submit Unknown Species' })).toBeDisabled();
  expect(within(dialog).getAllByText('Analyzing…')).toHaveLength(3);
  await act(async () => finishAnalysis({ ...size, predicted_height_m: 12 }));
  expect(await within(dialog).findByText('45 cm')).toBeInTheDocument();
  expect(within(dialog).getByText('12 m')).toBeInTheDocument();
  expect(within(dialog).getByText(/^[\d.]+ kg$/)).toBeInTheDocument();
  expect(within(dialog).getByLabelText('Treetop photo')).toBeInTheDocument();
  expect(within(dialog).getByRole('button', { name: 'Re-analyze' })).toBeEnabled();
  expect(await within(dialog).findByText('Preliminary estimate based on the suggested species.')).toBeInTheDocument();
  fireEvent.click(within(dialog).getByRole('button', { name: 'Back to measurements' }));
  expect(aiApi.submitUnknown).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole('button', { name: 'Submit Unknown Species' }));
  const reopened = await screen.findByRole('dialog', { name: 'Species needs expert review' });
  fireEvent.change(within(reopened).getByLabelText('Latitude'), { target: { value: '7.3' } });
  fireEvent.change(within(reopened).getByLabelText('Longitude'), { target: { value: '125.6' } });
  fireEvent.change(within(reopened).getByLabelText('Barangay'), { target: { value: 'New Visayas' } });
  const submit = within(reopened).getByRole('button', { name: 'Submit Unknown Species' });
  expect(screen.queryByRole('button', { name: 'Save Tree Record' })).toBeNull();
  expect(aiApi.submitUnknown).not.toHaveBeenCalled();
  fireEvent.click(submit);

  expect(await screen.findByRole('button', { name: 'Submitted for expert review' })).toBeDisabled();
  expect(storageApi.uploadPhoto).toHaveBeenLastCalledWith(original, 'unknown_species');
  expect(aiApi.submitUnknown).toHaveBeenCalledWith(expect.objectContaining({
    photo_url: 'https://example.test/tree.jpg',
    dbh_cm: 45,
    height_m: 12,
    location_description: '7.3, 125.6',
    barangay: 'New Visayas',
    ai_candidates: [{
      common_name: 'Narra', scientific_name: 'Pterocarpus indicus', confidence_percent: 74.99,
    }],
  }));
  expect(saveRecord).not.toHaveBeenCalled();
});

test('shows confidence for accepted species predictions', async () => {
  aiApi.identifyFromFile.mockResolvedValueOnce({
    common_name: 'Narra',
    scientific_name: 'Pterocarpus indicus',
    confidence_percent: 82.5,
  });
  render(<MemoryRouter><TreeForm onSubmit={vi.fn()} /></MemoryRouter>);
  fireEvent.change(screen.getByLabelText('Tree photo'), { target: { files: [original] } });
  expect(await screen.findByText('Confidence 82.5%.')).toBeInTheDocument();
  expect(screen.getByText(/Identified as Narra/)).toBeInTheDocument();
});
