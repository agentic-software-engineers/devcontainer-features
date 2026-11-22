export const appName = 'Dev Container Features';
export const basePath = '/devcontainer-features';
export const siteUrl = 'https://agentic-software-engineers.com';

export const gitConfig = {
  user: 'agentic-software-engineers',
  repo: 'devcontainer-features',
  branch: 'main',
};

/** the `.md` file of a page under /llms.mdx, `/index.md` for the overview */
export function markdownUrl(url: string) {
  return `${basePath}/llms.mdx${url === '/' ? '/index' : url.replace(/\/$/, '')}.md`;
}
