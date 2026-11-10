import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { aiApi } from '@/api/ai';
import TreeAgeEstimate from './TreeAgeEstimate';
vi.mock('@/api/ai', () => ({ aiApi: { estimateAge: vi.fn() } }));
beforeEach(() => aiApi.estimateAge.mockReset());
afterEach(cleanup);

test('uses DBH as headline, labels unverified rates and flags disagreement', async () => {
  aiApi.estimateAge.mockResolvedValue({ status: 'estimated', dbh_age_years: 17.6, height_age_years: 4.8,
    estimation_basis: 'ai_growth_guess', dimensions_disagree: true, source: null });
  render(<TreeAgeEstimate scientificName="Gmelina arborea" dbhCm={45} heightM={11} />);
  expect(await screen.findByText('About 18 years (estimated)')).toBeInTheDocument();
  expect(screen.getByText('AI growth estimate — source unverified')).toBeInTheDocument();
  expect(screen.getByText(/highly uncertain/)).toBeInTheDocument();
  expect(screen.queryByRole('link')).not.toBeInTheDocument();
});

test('height-only estimate is labeled and failure can retry', async () => {
  aiApi.estimateAge.mockRejectedValueOnce(new Error('offline')).mockResolvedValueOnce({
    status: 'estimated', height_age_years: 12.3, estimation_basis: 'ai_growth_guess' });
  render(<TreeAgeEstimate scientificName="Cocos nucifera" heightM={8} />);
  fireEvent.click(await screen.findByRole('button', { name: 'Retry age estimate' }));
  expect(await screen.findByText('About 12 years (estimated)')).toBeInTheDocument();
  expect(screen.getByText(/no DBH age calculation/)).toBeInTheDocument();
});

test('species changes discard late old age results', async () => {
  let finish;
  aiApi.estimateAge.mockReturnValueOnce(new Promise(resolve => { finish = resolve; }))
    .mockResolvedValueOnce({ status: 'estimated', dbh_age_years: 30 });
  const { rerender } = render(<TreeAgeEstimate scientificName="Gmelina arborea" dbhCm={45} />);
  await waitFor(() => expect(aiApi.estimateAge).toHaveBeenCalledTimes(1));
  rerender(<TreeAgeEstimate scientificName="Mangifera indica" dbhCm={45} />);
  expect(await screen.findByText('About 30 years (estimated)')).toBeInTheDocument();
  await act(async () => finish({ status: 'estimated', dbh_age_years: 18 }));
  expect(screen.getByText('About 30 years (estimated)')).toBeInTheDocument();
});
