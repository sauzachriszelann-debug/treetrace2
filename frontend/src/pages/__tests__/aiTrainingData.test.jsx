import { beforeEach, describe, expect, test, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import AITrainingData from '../AITrainingData';
import { trainingDataApi } from '@/api/trainingData';

vi.mock('@/api/trainingData', () => ({ trainingDataApi: { list: vi.fn(), exportPhotos: vi.fn(), manifest: vi.fn() } }));
const auth = { user: { role: 'admin' }, isLoadingAuth: false };
vi.mock('@/lib/AuthContext', () => ({ useAuth: () => auth }));
vi.mock('@/components/trees/TreePhotoPreview', () => ({ default: ({ alt }) => <div>{alt}</div> }));
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), warning: vi.fn() } }));

const row = { id: 'species:7', photo_url: 'https://example.test/tree.jpg',
  original_common_name: 'Mango', original_scientific_name: 'Mangifera indica', confidence_percent: 21.16,
  confirmed_common_name: 'Narra', confirmed_scientific_name: 'Pterocarpus indicus',
  reviewer_name: 'Expert Reviewer', reviewed_at: '2026-11-18T09:00:00Z', corrected: true, ready: true, issues: [] };
function mount() {
  return render(<QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}><AITrainingData /></QueryClientProvider>);
}
beforeEach(() => {
  vi.clearAllMocks(); auth.user = { role: 'admin' };
  trainingDataApi.list.mockResolvedValue({ total: 1, ready: 1, corrected: 1, items: [row] });
});

describe('admin reviewed training data', () => {
  test.each(['citizen', 'field_worker'])('denies %s and never fetches records', async role => {
    auth.user = { role }; mount();
    expect(screen.getByText(/Only admins/)).toBeInTheDocument();
    expect(trainingDataApi.list).not.toHaveBeenCalled();
  });
  test('shows original prediction, confirmed label, score and reviewer', async () => {
    mount();
    expect(await screen.findByText('Narra')).toBeInTheDocument();
    expect(screen.getByText('Mango')).toBeInTheDocument();
    expect(screen.getByText('Confidence: 21.16%')).toBeInTheDocument();
    expect(screen.getByText(/Reviewed by Expert Reviewer/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Export photos/ })).toBeDisabled();
  });
  test('legacy entries cannot be selected', async () => {
    trainingDataApi.list.mockResolvedValue({ total: 1, ready: 0, corrected: 1,
      items: [{ ...row, ready: false, issues: ['Reviewer/date not recorded.'] }] });
    mount();
    expect(await screen.findByRole('checkbox')).toBeDisabled();
    expect(screen.getByText('Reviewer/date not recorded.')).toBeInTheDocument();
  });
  test('exports only the selected reviewed IDs', async () => {
    vi.stubGlobal('URL', class extends URL { static createObjectURL() { return 'blob:export'; } static revokeObjectURL() {} });
    vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
    trainingDataApi.exportPhotos.mockResolvedValue({ blob: new Blob(['zip']), count: 1, failed: 0 });
    mount();
    fireEvent.click(await screen.findByRole('checkbox', { name: 'Select species:7' }));
    fireEvent.click(screen.getByRole('button', { name: /Export photos/ }));
    await waitFor(() => expect(trainingDataApi.exportPhotos).toHaveBeenCalledWith(['species:7']));
    vi.unstubAllGlobals();
  });
});
