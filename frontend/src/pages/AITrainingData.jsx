import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Download, RefreshCw, Database, CheckCircle2, PencilLine } from 'lucide-react';
import { useAuth } from '@/lib/AuthContext';
import { trainingDataApi } from '@/api/trainingData';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import TreePhotoPreview from '@/components/trees/TreePhotoPreview';
import { toast } from 'sonner';

function saveFile(blob, filename) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url; link.download = filename; link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export default function AITrainingData() {
  const { user, isLoadingAuth } = useAuth();
  const isAdmin = user?.role === 'admin';
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(0);
  const [selected, setSelected] = useState([]);
  const [exporting, setExporting] = useState(false);
  const { data, isLoading, isError, refetch } = useQuery({
    queryKey: ['ai-training-data', search, page],
    queryFn: () => trainingDataApi.list({ q: search, offset: page * 50, limit: 50 }),
    enabled: isAdmin,
  });
  if (isLoadingAuth) return <p className="p-6">Loading account.</p>;
  if (!isAdmin) return <div className="p-6"><h1 className="text-2xl font-semibold">AI Training Data</h1><p>Only admins can view or export reviewed training examples.</p></div>;

  const exportSelected = async () => {
    setExporting(true);
    try {
      const result = await trainingDataApi.exportPhotos(selected);
      saveFile(result.blob, 'treetrace_reviewed_photos.zip');
      if (result.count > 0) toast.success(`Exported ${result.count} unique photos. Check export_report.json for skipped files.`);
      else toast.warning('No photos exported. Open export_report.json in the ZIP for the reasons.');
    } catch { toast.error('Photo export failed. Refresh the list and try fewer photos.'); }
    finally { setExporting(false); }
  };
  const exportManifest = async () => {
    setExporting(true);
    try { saveFile(await trainingDataApi.manifest(), 'treetrace_reviewed_manifest.csv'); }
    catch { toast.error('Manifest export failed. Try again.'); }
    finally { setExporting(false); }
  };
  return <div className="mx-auto max-w-6xl space-y-6 p-4 sm:p-6">
    <div className="flex flex-wrap items-start justify-between gap-4">
      <div><h1 className="font-fraunces text-3xl font-semibold">AI Training Data</h1>
        <p className="mt-2 text-muted-foreground">Photos and labels confirmed through Tree Reviews, ready for the next model training session.</p></div>
      <Button variant="outline" onClick={() => { setSelected([]); refetch(); }}><RefreshCw className="mr-2 h-4 w-4" />Refresh</Button>
    </div>
    <div className="grid gap-3 sm:grid-cols-3">
      {[[Database, 'Reviewed examples', data?.total], [CheckCircle2, 'Ready to export', data?.ready], [PencilLine, 'Corrected predictions', data?.corrected]].map(([Icon, title, value]) =>
        <Card key={title}><CardContent className="flex items-center justify-between p-5"><div><p className="text-sm text-muted-foreground">{title}</p><p className="text-2xl font-semibold">{value ?? '-'}</p></div><Icon className="h-6 w-6 text-primary" /></CardContent></Card>)}
    </div>
    <div className="rounded-xl border bg-muted/30 p-4 text-sm">Confirmations appear here automatically. Exporting prepares data; it does not retrain or replace the AI model. Exact duplicate photos are grouped, and conflicting labels are excluded from the ZIP.</div>
    <div className="flex flex-wrap gap-3">
      <Input aria-label="Search reviewed species" className="sm:max-w-sm" placeholder="Search original or confirmed species" value={search} onChange={event => { setSearch(event.target.value); setPage(0); setSelected([]); }} />
      <Button disabled={exporting || !selected.length} onClick={exportSelected}><Download className="mr-2 h-4 w-4" />Export photos + labels ({selected.length}/20)</Button>
      <Button variant="outline" disabled={exporting || !data?.ready} onClick={exportManifest}>Export all ready labels (CSV)</Button>
    </div>
    {exporting && <p role="status">Preparing export. Photos are checked before packaging.</p>}
    {isLoading && <p role="status">Loading reviewed examples.</p>}
    {isError && <p role="alert">Reviewed examples could not load. Use Refresh to try again.</p>}
    {!isLoading && !isError && !data?.items?.length && <Card><CardContent className="p-8 text-center text-muted-foreground">No confirmed examples yet. Confirm a species in Tree Reviews to start collecting reviewed training data.</CardContent></Card>}
    <div className="grid gap-5 lg:grid-cols-2">
      {(data?.items || []).map(row => <Card key={row.id} className="overflow-hidden"><CardContent className="space-y-4 p-5">
        <div className="flex items-center justify-between gap-3"><label className="flex items-center gap-2 text-sm"><input type="checkbox" aria-label={`Select ${row.id}`} checked={selected.includes(row.id)} disabled={exporting || !row.ready || (!selected.includes(row.id) && selected.length >= 20)} onChange={event => setSelected(values => event.target.checked ? [...values, row.id] : values.filter(value => value !== row.id))} />{row.id}</label><Badge variant={row.ready ? 'default' : 'secondary'}>{row.ready ? 'Ready to export' : 'Needs completion'}</Badge></div>
        {row.photo_url ? <TreePhotoPreview src={row.photo_url} alt={`Reviewed ${row.confirmed_common_name || 'tree'}`} className="overflow-hidden rounded-lg border" thumbnailClassName="h-48 w-full bg-muted object-contain" /> : <div className="rounded-lg bg-muted p-8 text-center">Photo unavailable</div>}
        <div className="rounded-lg bg-muted/40 p-3"><p className="text-xs font-semibold uppercase text-muted-foreground">Original AI suggestion</p><p>{row.original_common_name || 'No AI prediction recorded'}</p><p className="text-sm italic">{row.original_scientific_name}</p><p className="mt-1 text-sm">Confidence: {Number.isFinite(row.confidence_percent) ? `${row.confidence_percent.toFixed(2)}%` : 'Unavailable'}</p></div>
        <div><p className="text-xs font-semibold uppercase text-primary">Expert-confirmed label</p><p className="text-lg font-semibold">{row.confirmed_common_name || 'Missing common name'}</p><p className="italic">{row.confirmed_scientific_name || 'Missing scientific name'}</p>{row.corrected && <Badge variant="outline" className="mt-2">AI prediction corrected</Badge>}</div>
        <p className="text-sm text-muted-foreground">Reviewed by {row.reviewer_name || 'Not recorded'}{row.reviewed_at ? ` on ${new Date(row.reviewed_at).toLocaleString()}` : ''}</p>
        {!!row.issues.length && <ul className="space-y-1 text-sm text-amber-800">{row.issues.map(issue => <li key={issue}>{issue}</li>)}</ul>}
      </CardContent></Card>)}
    </div>
    {!!data?.total && <div className="flex items-center justify-between"><Button variant="outline" disabled={page === 0 || exporting} onClick={() => { setPage(value => value - 1); setSelected([]); }}>Previous</Button><p className="text-sm">Page {page + 1} of {Math.ceil(data.total / 50)}</p><Button variant="outline" disabled={(page + 1) * 50 >= data.total || exporting} onClick={() => { setPage(value => value + 1); setSelected([]); }}>Next</Button></div>}
  </div>;
}
