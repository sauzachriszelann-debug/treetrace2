import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeAll, expect, test, vi } from 'vitest';
import PublicPortal from '../PublicPortal';

const trees = [
  {id:1,common_name:'Mango',scientific_name:'Mangifera indica',barangay:'New Visayas',health_status:'Healthy',lat:7.31,lng:125.67},
  {id:2,common_name:'Narra',scientific_name:'Pterocarpus indicus',barangay:'San Vicente',health_status:'Healthy',lat:7.30,lng:125.68},
  {id:3,common_name:'Gmelina',barangay:' New Visayas ',health_status:'Poor',lat:7.31,lng:125.67},
];
vi.mock('@tanstack/react-query', () => ({useQuery: () => ({data:trees,isLoading:false})}));
vi.mock('react-leaflet', () => {
  const Group = ({children}) => <div>{children}</div>;
  const LayersControl = Object.assign(Group,{BaseLayer:Group});
  return {MapContainer:Group,TileLayer:()=>null,Marker:Group,Popup:Group,LayersControl,LayerGroup:Group};
});
beforeAll(() => { Element.prototype.scrollIntoView = vi.fn(); });
afterEach(cleanup);

function choose(label, name) {
  fireEvent.keyDown(screen.getByRole('combobox',{name:label}),{key:'ArrowDown'});
  fireEvent.keyDown(screen.getByRole('option',{name,exact:true}),{key:'Enter'});
}

test('barangay dropdown filters both map and list, combines with health and resets', () => {
  render(<MemoryRouter><PublicPortal /></MemoryRouter>);
  choose('Filter by barangay','New Visayas');
  expect(screen.getByText('2 trees mapped')).toBeVisible();
  expect(screen.queryByText('Narra')).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole('button',{name:'List View'}));
  expect(screen.getByText('2 trees found')).toBeVisible();
  choose('Filter by health status','Healthy');
  expect(screen.getByText('1 trees found')).toBeVisible();
  expect(screen.queryByText('Gmelina')).not.toBeInTheDocument();
  choose('Filter by barangay','All Barangays');
  expect(screen.getByText('2 trees found')).toBeVisible();
});

test('dropdown includes barangays without trees and search remains independent', () => {
  render(<MemoryRouter><PublicPortal /></MemoryRouter>);
  choose('Filter by barangay','New Visayas');
  fireEvent.change(screen.getByRole('textbox',{name:'Search trees'}),{target:{value:'Mangifera'}});
  expect(screen.getByText('1 trees mapped')).toBeVisible();
  choose('Filter by barangay','San Vicente');
  expect(screen.getByText('No GPS-tagged trees match your filter.')).toBeVisible();
  fireEvent.keyDown(screen.getByRole('combobox',{name:'Filter by barangay'}),{key:'ArrowDown'});
  expect(screen.getAllByRole('option').length).toBe(41);
});
