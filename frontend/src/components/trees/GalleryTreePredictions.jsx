import { createPortal } from 'react-dom';
import { useEffect, useRef, useState } from 'react';
import { aiApi } from '@/api/ai';
import { Button } from '@/components/ui/button';
import { usePhotoUrl } from "@/lib/usePhotoUrl";
import TreePhotoPreview from "@/components/trees/TreePhotoPreview";
import TreeAgeEstimate from './TreeAgeEstimate';

function metric(result, key, max) {
  const value = result?.[key];
  return result?.status === 'predicted' && result.method === 'gallery_yolo_vision_prediction' &&
    result.quality === 'unvalidated' && result.prediction_basis === 'visual_appearance' &&
    result.validated_accuracy === false && result.fallback !== true &&
    (result.trunk_detected === true || (result.target_source === 'ai_visual' && result.target_identified === true)) &&
    typeof value === 'number' && Number.isFinite(value) && value >= 1 && value <= max ? value : null;
}

function requestError(error) {
  const status = error?.response?.status;
  if (status === 429) return 'AI prediction is temporarily busy. Try again later.';
  if ([401, 403].includes(status)) return 'Prediction access denied. Sign in again or check deployment access.';
  if (status === 413) return 'Photo exceeds the upload limit. Choose a smaller image.';
  return error?.response ? 'Prediction could not complete. Try again.' : error?.message || 'Check your connection and try again.';
}

export default function GalleryTreePredictions({ file, scientificName, onDimensions, onAnalysisPending, onAgeEstimated,
  ageDbhCm, ageHeightM, portalTarget, preliminarySpecies = false, dimensionsSource = 'ai_prediction' }) {
  const [prediction, setPrediction] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [retry, setRetry] = useState(0);
  const [top, setTop] = useState(null);
  const [base, setBase] = useState(null);
  const [pendingSupplement, setPendingSupplement] = useState(null);
  const [supplementLoading, setSupplementLoading] = useState(false);
  const [supplementError, setSupplementError] = useState(null);
  const epoch = useRef(0);
  const pairController = useRef(null);
  const acceptedPhotos = useRef(null);
  const originalUrl = usePhotoUrl(file);
  const topUrl = usePhotoUrl(top);
  const baseUrl = usePhotoUrl(base);
  const pendingUrl = usePhotoUrl(pendingSupplement?.file);

  useEffect(() => {
    let active = true;
    const controller = new AbortController();
    epoch.current++;
    setPrediction(null); setError(null); setLoading(true);
    const photos = acceptedPhotos.current?.file === file ? acceptedPhotos.current : null;
    if (!photos) { setTop(null); setBase(null); }
    setSupplementError(null); setSupplementLoading(false);
    setPendingSupplement(null);
    Promise.resolve().then(() => aiApi.predictGallerySize(file, {
      ...(photos?.top && { treetopFile: photos.top }),
      ...(photos?.base && { treebaseFile: photos.base }),
      signal: controller.signal,
    }))
      .then(result => { if (active) setPrediction(result); })
      .catch(e => { if (active) setError(requestError(e)); })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; epoch.current++; controller.abort(); pairController.current?.abort(); };
  }, [file, retry]);

  const selectSupplement = (event, kind) => {
    const selected = event.target.files?.[0];
    event.target.value = '';
    if (selected) setPendingSupplement({ file: selected, kind });
  };

  const confirmSupplement = async () => {
    if (!pendingSupplement || supplementLoading) return;
    const { file: selected, kind } = pendingSupplement;
    setPendingSupplement(null);
    const request = epoch.current;
    const controller = new AbortController();
    pairController.current?.abort();
    pairController.current = controller;
    const baseFile = kind === 'base' ? selected : base;
    const topFile = kind === 'top' ? selected : top;
    setSupplementLoading(true); setSupplementError(null);
    try {
      const result = await aiApi.predictGallerySize(file, {
        ...(topFile && { treetopFile: topFile }),
        ...(baseFile && { treebaseFile: baseFile }),
        signal: controller.signal,
      });
      if (request !== epoch.current || controller.signal.aborted) return;
      if (baseFile) {
        if (result.treebase_photo_used === true && result.target_identified === true) {
          acceptedPhotos.current = { file, base: baseFile, top: topFile };
          setBase(baseFile);
          setTop(topFile);
          setPrediction(result);
        } else {
          setSupplementError(result.dbh_reason || result.reason || 'Show where the same trunk meets the ground.');
        }
        return;
      }
      const height = metric(result, 'predicted_height_m', 80);
      if (result.treetop_photo_used !== true || height == null || result.target_identified !== true) {
        setSupplementError(result.height_reason || result.reason || 'Use a photo showing this same tree’s top and overlapping branches.');
        return;
      }
      acceptedPhotos.current = { file, base: baseFile, top: topFile };
      setTop(topFile);
      setPrediction(current => ({
        ...current, status: 'predicted', target_identified: true,
        predicted_height_m: height, needs_treetop_photo: false, treetop_photo_used: true,
        height_reason: result.height_reason, height_reason_code: result.height_reason_code,
        uncertainties: [...(current.uncertainties || []).filter(v => !v.startsWith('Height:')),
        ...(result.uncertainties || []).filter(v => v.startsWith('Height:'))],
      }));
    } catch (e) { if (request === epoch.current && !controller.signal.aborted) setSupplementError(requestError(e)); }
    finally { if (request === epoch.current && !controller.signal.aborted) setSupplementLoading(false); }
  };

  useEffect(() => {
    onAnalysisPending?.(loading || supplementLoading);
  }, [loading, supplementLoading, onAnalysisPending]);

  const dbh = metric(prediction, 'predicted_dbh_cm', 300);
  const height = metric(prediction, 'predicted_height_m', 80);
  const dbhIssue = dbh === null ? prediction?.dbh_reason : null;
  const heightIssue = height === null ? prediction?.height_reason : null;
  const analysisIssue = prediction?.status !== 'predicted' && !dbhIssue && !heightIssue
    ? prediction?.reason
    : null;
  useEffect(() => { onDimensions?.({ dbhCm: dbh, heightM: height }); }, [dbh, height, onDimensions]);
  const needsBase = base || prediction?.needs_treebase_photo || prediction?.dbh_reason_code === 'base_hidden' || prediction?.height_reason_code === 'base_hidden';
  const needsTop = top || prediction?.needs_treetop_photo || prediction?.height_reason_code === 'top_hidden' || prediction?.treetop_photo_used;
  const analysis = <section aria-label="Tree analysis" className="space-y-4 rounded-xl border border-primary/20 bg-primary/5 p-4">
    <div><h2 className="font-semibold">DBH and Height</h2>
      <p className="text-sm text-muted-foreground">Photo estimates. Review before saving.</p></div>
    <div className="flex flex-wrap gap-3">
      {!portalTarget && <TreePhotoPreview src={originalUrl} label="Original tree photo" className="rounded-lg border p-1" thumbnailClassName="h-44 max-w-full object-contain" />}
      {prediction?.preview_png && <TreePhotoPreview src={`data:image/png;base64,${prediction.preview_png}`} label="Trunk detection" className="rounded-lg border p-1" thumbnailClassName="h-44 max-w-full object-contain" />}
    </div>
    {loading ? <p role="status">Detecting trunk and estimating DBH and height…</p> : error ? <>
      <p role="alert">{error}</p><Button type="button" variant="outline" onClick={() => setRetry(n => n + 1)}>{portalTarget ? "Re-analyze" : "Retry analysis"}</Button>
    </> : <>
      <div className="grid gap-2 sm:grid-cols-2">
        <p>DBH (cm): <strong>{dbh ?? 'Unavailable'}</strong></p>
        <p>Height (m): <strong>{height ?? 'Unavailable'}</strong></p>
      </div>
      {prediction?.detection_note && <p className="text-sm">{prediction.detection_note}</p>}
      {(dbhIssue || heightIssue || analysisIssue) && (
        <details>
          <summary className="cursor-pointer text-sm">Analysis details</summary>
          {dbhIssue && <p className="text-sm">DBH: {dbhIssue}</p>}
          {heightIssue && <p className="text-sm">Height: {heightIssue}</p>}
          {analysisIssue && <p className="text-sm text-muted-foreground">{analysisIssue}</p>}
        </details>
      )}
      {!prediction?.trunk_detected && <Button type="button" variant="outline" onClick={() => setRetry(n => n + 1)}>Retry trunk detection</Button>}
      {prediction?.treetop_photo_used && <p className="text-sm">Height estimated using your original photo and added treetop photo.</p>}
      {needsBase && <div className="space-y-2 border-t pt-3">
        <p className="text-sm">Show where the trunk meets the ground. Include part of the trunk visible in the original photo so the views can be matched.</p>
        <TreePhotoPreview src={baseUrl} label="Added tree base photo" className="rounded-lg border p-1" thumbnailClassName="h-44 max-w-full object-contain" />
        <label className="block text-sm font-medium">{base ? 'Replace tree base photo' : 'Add tree base photo'}
          <input aria-label="Tree base photo" type="file" accept="image/jpeg,image/png,image/webp" disabled={supplementLoading}
            onChange={event => selectSupplement(event, 'base')} className="mt-1 block max-w-full text-sm" />
        </label>
      </div>}
      {needsTop && <div className="space-y-2 border-t pt-3">
        <p className="text-sm">Add the treetop of this same tree. Stay in the same position and include overlapping trunk or branches so both photos can be matched.</p>
        <TreePhotoPreview src={topUrl} label="Added treetop photo" className="rounded-lg border p-1" thumbnailClassName="h-44 max-w-full object-contain" />
        <label className="block text-sm font-medium">{top ? 'Replace treetop photo' : 'Add treetop photo'}
          <input aria-label="Treetop photo" type="file" accept="image/jpeg,image/png,image/webp" disabled={supplementLoading} onChange={event => selectSupplement(event, 'top')}
            className="mt-1 block max-w-full text-sm" />
        </label>
      </div>}
      {pendingSupplement && <div className="space-y-2 rounded-lg border border-border bg-card p-3">
        <TreePhotoPreview src={pendingUrl} label={pendingSupplement.kind === 'base' ? 'New tree base photo' : 'New treetop photo'} className="rounded-lg border p-1" thumbnailClassName="h-44 max-w-full object-contain" />
        <p className="text-sm">Do the original and added photos show the exact same tree?</p>
        <div className="flex flex-wrap gap-2">
          <Button type="button" size="sm" onClick={confirmSupplement}>Yes, analyze photos</Button>
          <Button type="button" size="sm" variant="outline" onClick={() => setPendingSupplement(null)}>Cancel</Button>
        </div>
      </div>}
      {supplementLoading && <p role="status">Checking added photos.</p>}
      {supplementError && <p role="alert">{supplementError}</p>}
      <TreeAgeEstimate onEstimated={onAgeEstimated} scientificName={scientificName}
        preliminarySpecies={preliminarySpecies}
        dbhCm={ageDbhCm === undefined ? dbh : ageDbhCm}
        heightM={ageHeightM === undefined ? height : ageHeightM}
        dimensionsSource={dimensionsSource} />
      {(portalTarget || prediction?.status !== 'predicted') && <Button disabled={supplementLoading} type="button" variant="outline" onClick={() => setRetry(n => n + 1)}>{portalTarget ? "Re-analyze" : "Retry analysis"}</Button>}
    </>}
  </section>;
  return portalTarget ? createPortal(analysis, portalTarget) : analysis;
}
