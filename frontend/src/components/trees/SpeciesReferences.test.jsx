import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, expect, test } from 'vitest';
import { ReferencePhotos, SpeciesComparisons } from './SpeciesReferences';

afterEach(cleanup);
const photo = { url:'/species-reference/mango.jpg', caption:'Mango reference',
  author:'Botanical photographer', license:'CC BY 4.0',
  source_url:'https://www.inaturalist.org/photos/123', license_url:'https://creativecommons.org/licenses/by/4.0/' };

test('reference image can expand and keeps its author, source and license', () => {
  render(<ReferencePhotos photos={[photo]} />);
  expect(screen.getByText(/not this individual tree/)).toBeVisible();
  expect(screen.getByRole('link', {name:photo.author})).toHaveAttribute('href',photo.source_url);
  expect(screen.getByRole('link', {name:photo.license})).toHaveAttribute('href',photo.license_url);
  fireEvent.click(screen.getByRole('button', {name:'Expand Mango reference'}));
  expect(screen.getByRole('dialog')).toBeVisible();
});

test('comparison keeps the comparison taxon and distinction separate from AI prediction', () => {
  render(<SpeciesComparisons records={[{scientific_name:'Syzygium cumini',common_name:'Duhat',
    comparison:'Compare mature fruit.', botanical_source:'https://www.nparks.gov.sg/florafaunaweb/flora/3/1/3158',photos:[photo]}]} />);
  expect(screen.getByText('Syzygium cumini')).toBeVisible();
  expect(screen.getByText(/not additional AI predictions/)).toBeVisible();
  expect(screen.getByText('Compare mature fruit.')).toBeVisible();
});

test('missing reference photos do not reuse the inventory tree photo', () => {
  const {container}=render(<ReferencePhotos />);
  expect(container.querySelector('img')).toBeNull();
});
