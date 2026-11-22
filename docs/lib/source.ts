import { llms, loader } from 'fumadocs-core/source';
import { defineDocs } from 'fumadocs-mdx/macro';
import { metaSchema, pageSchema } from 'fumadocs-core/source/schema';
import { basePath, siteUrl } from './shared';

const docs = defineDocs({
  dir: 'content/docs',
  docs: {
    schema: pageSchema,
    postprocess: {
      includeProcessedMarkdown: true,
    },
  },
  meta: {
    schema: metaSchema,
  },
});

// the docs are the whole site, so their pages start at the root
export const source = loader({
  baseUrl: '/',
  source: docs.toFumadocsSource(),
});

export const docsLlms = llms(source, {
  renderPage: async (page) => `# ${page.data.title} (${siteUrl}${basePath}${page.url})

${await page.data.getText('processed')}`,
  // link to the files under /llms.mdx, with the full address so agents can follow them
  renderUrl: (item) =>
    /^\/.*\.(md|txt)$/.test(item.url)
      ? `${siteUrl}${basePath}/llms.mdx${item.url}`
      : `${siteUrl}${basePath}${item.url}`,
});
