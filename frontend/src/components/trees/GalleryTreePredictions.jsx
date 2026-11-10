import { useEffect, useRef, useState } from 'react';
import { aiApi } from '@/api/ai';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogTitle, DialogTrigger } from '@/components/ui/dialog';
import TreeAgeEstimate from './TreeAgeEstimate';

function metric(result, key, max) {
  const value = result?.[key];
  return result?.status === 'predicted' && result.method === 'gallery_yolo_vision_prediction' &&
    result.quality === 'unvalidated' && result.prediction_basis === 'visual_appearance' &&
    result.validated_accuracy === false && result.fallback !== true &&
    (result.trunk_detected === true || (result.target_source === 'ai_visual' && result.target_identified === true)) &&
    typeof value === 'number' && Number.isFinite(value) && value >= 1 && value <= max ? value : null;
}

function usePhotoUrl(file) {
  const [url, setUrl] = useState(null);
  useEffect(() => {
    if (!file) { setUrl(null); return; }
    const next = URL.createObjectURL(file);
    setUrl(next);
    return () => URL.revokeObjectURL(next);
  }, [file]);
  return url;
}

function Photo({ src, label }) {
  if (!src) return null;
  return <Dialog><DialogTrigger asChild>
    <button type="button" aria-label={`Expand ${label}`} className="rounded-lg border p-1 focus-visible:ring-2 focus-visible:ring-primary">
      <img src={src} alt={label} className="h-44 max-w-full object-contain" />
    </button>
  </DialogTrigger><DialogContent className="max-w-4xl">
    <DialogTitle>{label}</DialogTitle>
    <img src={src} alt={label} className="max-h-[75vh] w-full object-contain" />
  </DialogContent></Dialog>;
}

function requestError(error) {
  const status = error?.response?.status;
  if ([402, 429].includes(status)) return 'AI request limit reached. Try again later.';
  if ([401, 403].includes(status)) return 'Prediction access denied. Sign in again or check deployment access.';
  if (status === 413) return 'Photo exceeds the upload limit. Choose a smaller image.';
  return error?.response ? 'Prediction could not complete. Try again.' : error?.message || 'Check your connection and try again.';
}

export default function GalleryTreePredictions({ file, scientificName }) {
  const [prediction, setPrediction] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [retry, setRetry] = useState(0);
  const [top, setTop] = useState(null);
  const [topLoading, setTopLoading] = useState(false);
  const [topError, setTopError] = useState(null);
  const epoch = useRef(0);
  const pairController = useRef(null);
  const originalUrl = usePhotoUrl(file);
  const topUrl = usePhotoUrl(top);

  useEffect(() => {
    let active = true;
    const controller = new AbortController();
    epoch.current++;
    setPrediction(null); setError(null); setLoading(true);
    setTop(null); setTopError(null); setTopLoading(false);
    Promise.resolve().then(() => aiApi.predictGallerySize(file, { signal: controller.signal }))
      .then(result => { if (active) setPrediction(result); })
      .catch(e => { if (active) setError(requestError(e)); })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; epoch.current++; controller.abort(); pairController.current?.abort(); };
  }, [file, retry]);

  const addTreetop = async event => {
    const selected = event.target.files?.[0];
    event.target.value = '';
    if (!selected) return;
    const request = epoch.current;
    const controller = new AbortController();
    pairController.current?.abort();
    pairController.current = controller;
    setTop(selected); setTopLoading(true); setTopError(null);
    try {
      const result = await aiApi.predictGallerySize(file, { treetopFile: selected, signal: controller.signal });
      if (request !== epoch.current || controller.signal.aborted) return;
      const height = metric(result, 'predicted_height_m', 80);
      if (result.treetop_photo_used !== true || height == null || result.target_identified !== true) {
        setTopError(result.height_reason || result.reason || 'Use a photo showing this same tree’s top and overlapping branches.');
        return;
      }
      setPrediction(current => ({ ...current, status: 'predicted', target_identified: true,
        predicted_height_m: height, needs_treetop_photo: false, treetop_photo_used: true,
        height_reason: result.height_reason, height_reason_code: result.height_reason_code,
        uncertainties: [...(current.uncertainties || []).filter(v => !v.startsWith('Height:')),
          ...(result.uncertainties || []).filter(v => v.startsWith('Height:'))],
      }));
    } catch (e) { if (request === epoch.current && !controller.signal.aborted) setTopError(requestError(e)); }
    finally { if (request === epoch.current) setTopLoading(false); }
  };

  const dbh = metric(prediction, 'predicted_dbh_cm', 300);
  const height = metric(prediction, 'predicted_height_m', 80);
  const needsTop = prediction?.needs_treetop_photo || prediction?.height_reason_code === 'top_hidden' || prediction?.treetop_photo_used;
  return <section aria-label="Gallery tree predictions" className="space-y-4 rounded-xl border border-primary/20 bg-primary/5 p-4">
    <div><h2 className="font-semibold">AI-predicted size</h2>
      <p className="text-sm text-muted-foreground">Unvalidated appearance-based predictions. No reference object is required. These values are not saved as measurements or used for carbon calculations.</p></div>
    <div className="flex flex-wrap gap-3">
      <Photo src={originalUrl} label="Original tree photo" />
      {prediction?.preview_png && <Photo src={`data:image/png;base64,${prediction.preview_png}`} label="Trunk detection" />}
    </div>
    {loading ? <p role="status">Detecting trunk and predicting DBH and height…</p> : error ? <>
      <p role="alert">{error}</p><Button type="button" variant="outline" onClick={() => setRetry(n => n + 1)}>Retry size prediction</Button>
    </> : <>
      <div className="grid gap-2 sm:grid-cols-2">
        <p>Predicted DBH (cm): <strong>{dbh ?? 'Unavailable'}</strong></p>
        <p>Predicted height (m): <strong>{height ?? 'Unavailable'}</strong></p>
      </div>
      {prediction?.detection_note && <p className="text-sm">{prediction.detection_note}</p>}
      {prediction?.dbh_reason && <p className="text-sm">DBH: {prediction.dbh_reason}</p>}
      {prediction?.height_reason && <p className="text-sm">Height: {prediction.height_reason}</p>}
      <p className="text-sm text-muted-foreground">{prediction?.reason}</p>
      {prediction?.treetop_photo_used && <p className="text-sm">Height predicted using your original photo and added treetop photo.</p>}
      {needsTop && <div className="space-y-2 border-t pt-3">
        <p className="text-sm">Add the treetop of this same tree. Stay in the same position and include overlapping trunk or branches so both photos can be matched.</p>
        <Photo src={topUrl} label="Added treetop photo" />
        <label className="block text-sm font-medium">{top ? 'Replace treetop photo' : 'Add treetop photo'}
          <input aria-label="Treetop photo" type="file" accept="image/jpeg,image/png,image/webp" disabled={topLoading} onChange={addTreetop}
            className="mt-1 block max-w-full text-sm" />
        </label>
        {topLoading && <p role="status">Checking treetop photo…</p>}
        {topError && <p role="alert">{topError}</p>}
      </div>}
      <TreeAgeEstimate scientificName={scientificName} dbhCm={dbh} heightM={height} />
      {prediction?.status !== 'predicted' && <Button type="button" variant="outline" onClick={() => setRetry(n => n + 1)}>Retry size prediction</Button>}
    </>}
  </section>;
}
