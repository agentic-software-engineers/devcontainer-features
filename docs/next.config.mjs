import { createMDX } from 'fumadocs-mdx/next';
import { basePath } from './lib/shared.ts';

const withMDX = createMDX();

/** @type {import('next').NextConfig} */
const config = {
  // a static site for GitHub Pages, served under the org's domain at /devcontainer-features
  output: 'export',
  basePath,
  trailingSlash: true,
  images: { unoptimized: true },
  reactStrictMode: true,
};

export default withMDX(config);
