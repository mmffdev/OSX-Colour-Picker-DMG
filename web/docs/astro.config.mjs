// docs.colorgain.com. Content comes from ../../Help/Resources through src/help-loader.mjs,
// so the app's Help menu and this site read the same files.
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  site: 'https://docs.colorgain.com',
  trailingSlash: 'always',
  integrations: [
    starlight({
      title: 'Colorgain',
      description: 'Help for Colorgain, the colour management and proofing system for 2D, 3D, video, design and print.',
      customCss: ['./src/styles/colorgain.css'],
      components: {
        ThemeProvider: './src/components/LightOnly.astro',
        ThemeSelect: './src/components/Empty.astro',
      },
      sidebar: [{ label: 'Help', items: [{ autogenerate: { directory: 'help' } }] }],
      pagination: true,
      lastUpdated: false,
      credits: false,
      social: [{ icon: 'discourse', label: 'Forum', href: 'https://forum.colorgain.com' }],
    }),
  ],
});
