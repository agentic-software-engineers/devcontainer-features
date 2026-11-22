import type { Metadata } from 'next';
import { GeistSans } from 'geist/font/sans';
import { GeistMono } from 'geist/font/mono';
import { Provider } from '@/components/provider';
import { appName, basePath, siteUrl } from '@/lib/shared';
import './global.css';

export const metadata: Metadata = {
  metadataBase: new URL(`${siteUrl}${basePath}/`),
  title: { template: `%s · ${appName}`, default: appName },
  icons: { icon: `${basePath}/logo.svg` },
};

export default function Layout({ children }: LayoutProps<'/'>) {
  return (
    <html lang="en" className={`dark ${GeistSans.variable} ${GeistMono.variable}`} suppressHydrationWarning>
      <body className="flex min-h-screen flex-col font-sans antialiased">
        <Provider>{children}</Provider>
      </body>
    </html>
  );
}
