import TreePhotoPreview from './TreePhotoPreview';

export function ReferencePhotos({ photos = [] }) {
  if (!photos.length) return null;
  return <div className="space-y-3">
    <p className="text-xs text-muted-foreground">Botanical examples, not this individual tree.</p>
    <div className="flex gap-4 overflow-x-auto pb-2">
      {photos.map(photo => <figure key={photo.source_url} className="w-56 shrink-0 space-y-2">
        <TreePhotoPreview src={photo.url} label={photo.caption}
          className="w-full rounded-xl border bg-muted/20"
          thumbnailClassName="h-44 w-full rounded-xl object-contain" />
        <figcaption className="text-xs leading-relaxed">
          <p>{photo.caption}</p>
          <a href={photo.source_url} target="_blank" rel="noopener noreferrer" className="underline">{photo.author || 'Photo source'}</a>
          {' · '}<a href={photo.license_url} target="_blank" rel="noopener noreferrer" className="underline">{photo.license}</a>
        </figcaption>
      </figure>)}
    </div>
  </div>;
}

export function SpeciesComparisons({ records = [] }) {
  if (!records.length) return null;
  return <div className="space-y-4">
    <p className="text-xs text-muted-foreground">Botanical comparisons, not additional AI predictions.</p>
    {records.map(record => <article key={record.scientific_name} className="space-y-3 rounded-xl border p-4">
      <div><p className="font-semibold">{record.common_name}</p><p className="italic text-sm">{record.scientific_name}</p></div>
      <ReferencePhotos photos={record.photos} />
      <p className="font-semibold text-sm">What to compare</p>
      <p className="text-sm leading-relaxed">{record.comparison}</p>
      <a href={record.botanical_source} target="_blank" rel="noopener noreferrer" className="text-xs underline">Botanical source</a>
    </article>)}
  </div>;
}
