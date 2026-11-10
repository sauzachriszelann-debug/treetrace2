import { useEffect, useState } from 'react';
import { aiApi } from '@/api/ai';
import { Button } from '@/components/ui/button';

const positive = value => typeof value === 'number' && Number.isFinite(value) && value > 0 ? value : null;

export default function TreeAgeEstimate({ scientificName, dbhCm, heightM, dimensionsSource = 'ai_prediction' }) {
  const [state, setState] = useState({ loading: true });
  const [retry, setRetry] = useState(0);
  useEffect(() => {
    if (!scientificName?.trim() || (!positive(dbhCm) && !positive(heightM))) return;
    let active = true;
    const controller = new AbortController();
    setState({ loading: true });
    const timer = setTimeout(() => Promise.resolve().then(() => aiApi.estimateAge({ scientific_name: scientificName.trim(),
      dbh_cm: positive(dbhCm), height_m: positive(heightM), dimensions_source: dimensionsSource,
    }, { signal: controller.signal })).then(result => {
      if (active) setState({ result });
    }).catch(error => {
      if (active) setState({ error: [402, 429].includes(error?.response?.status)
        ? 'AI age request limit reached. Try again later.' : 'Age estimate could not load. Try again.' });
    }), 250);
    return () => { active = false; clearTimeout(timer); controller.abort(); };
  }, [scientificName, dbhCm, heightM, dimensionsSource, retry]);

  if (!scientificName?.trim()) return <p className="text-sm text-muted-foreground">Age needs an identified species.</p>;
  if (!positive(dbhCm) && !positive(heightM)) return <p className="text-sm text-muted-foreground">Age needs a DBH or height value.</p>;
  const age = state.result;
  const primary = positive(age?.dbh_age_years) ?? positive(age?.height_age_years);
  let sourceUrl;
  try { if (new URL(age?.source?.url).protocol === 'https:') sourceUrl = age.source.url; } catch { /* No verified source URL. */ }
  return <section aria-label="Estimated age" className="rounded-xl border p-4 space-y-2">
    <h3 className="font-semibold">Estimated age</h3>
    {state.loading ? <p role="status">Checking growth data and estimating age…</p> : state.error ? <>
      <p role="alert">{state.error}</p>
      <Button type="button" variant="outline" onClick={() => setRetry(n => n + 1)}>Retry age estimate</Button>
    </> : <>
      <p className="text-sm">{age?.estimation_basis === 'ai_growth_guess'
        ? 'AI growth estimate — source unverified' : age?.source ? 'Published growth data' : 'Growth data unavailable'}</p>
      <p className="text-xl font-bold">{age?.status === 'estimated' && primary
        ? primary < 1 ? 'Less than 1 year (estimated)' : `About ${Math.round(primary)} ${Math.round(primary) === 1 ? 'year' : 'years'} (estimated)`
        : 'Age unknown'}</p>
      {positive(age?.dbh_age_years) ? <p className="text-sm">Based on DBH and this species’ diameter growth rate.
        {positive(age?.height_age_years) ? ' Height is a cross-check.' : ' Height is unavailable for a cross-check.'}</p>
        : positive(age?.height_age_years) ? <p className="text-sm">Based on height and this species’ height growth rate; no DBH age calculation is available.</p> : null}
      <p className="text-sm text-muted-foreground">Approximate age; growth varies with site, age and management.</p>
      <details><summary className="cursor-pointer">Calculation details and source</summary>
        <div className="mt-2 space-y-2 text-sm text-muted-foreground">
          {age?.dimensions_disagree && <p className="text-amber-800">DBH and height imply different ages under these growth rates. Having both values does not make them agree; the age estimate is highly uncertain.</p>}
          {age?.dbh_age_years != null && <p>From DBH: about {age.dbh_age_years} years</p>}
          {age?.height_age_years != null && <p>From height: about {age.height_age_years} years</p>}
          <p>{age?.reason}</p>
          {Object.entries(age?.growth_rates || {}).map(([key, rates]) => Array.isArray(rates) && rates.length === 3 && rates.every(Number.isFinite) &&
            <p key={key}>{key === 'dbh_cm_per_year' ? 'Diameter growth' : 'Height growth'}: {rates[0].toFixed(2)}–{rates[2].toFixed(2)} {key === 'dbh_cm_per_year' ? 'cm/year' : 'm/year'}</p>)}
          {age?.assumptions && <p>{age.assumptions}</p>}
          {age?.source && <><p>{age.source.citation}</p><p>{age.source.context}</p></>}
          {sourceUrl && <a className="underline" href={sourceUrl} target="_blank" rel="noopener noreferrer">Read growth study</a>}
        </div>
      </details>
    </>}
  </section>;
}
