import { defineCollection } from 'astro:content';
import { docsSchema } from '@astrojs/starlight/schema';
import { helpLoader } from './help-loader.mjs';

// The docs collection is the app's help folder, read in place. Nothing is copied.
export const collections = {
  docs: defineCollection({
    loader: helpLoader({ base: '../../Help/Resources', exclude: ['Legacy'] }),
    schema: docsSchema(),
  }),
};
