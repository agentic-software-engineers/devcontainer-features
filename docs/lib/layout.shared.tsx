import Image from 'next/image';
import type { BaseLayoutProps } from 'fumadocs-ui/layouts/shared';
import { appName, basePath, gitConfig, siteUrl } from './shared';

export function baseOptions(): BaseLayoutProps {
  return {
    nav: {
      title: (
        <>
          <Image src={`${basePath}/logo.svg`} alt="" width={24} height={24} />
          {appName}
        </>
      ),
    },
    links: [{ text: 'Agentic Software Engineers', url: siteUrl, external: true }],
    githubUrl: `https://github.com/${gitConfig.user}/${gitConfig.repo}`,
  };
}
