import { source } from '@/lib/source';
import { createFromSource } from 'fumadocs-core/search/server';

// written once at build time as a static file the browser searches
export const revalidate = false;

export const { staticGET: GET } = createFromSource(source, {
  language: 'english',
});
