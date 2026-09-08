// dsh SearXNG search provider plugin — no dependencies
// Uses local SearXNG instance (free, unlimited, no API key)
//
// FIX (2026-09-08): SearXNG's JSON API puts infobox-type results (the
// standard-article hits from the wikipedia engine) in `infoboxes[]`,
// NOT in `results[]`. The old version only read `data.results`, so any
// query whose only hits were wikipedia articles came back empty
// ("No results found.") even though SearXNG had found them.
// Now both arrays are merged.

import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

export const inject = ["web"];
export const name = 'web-search-searxng';

export function apply(ctx) {
  if (!ctx.web || typeof ctx.web.registerSearchProvider !== 'function') {
    console.error('[searxng] ctx.web not available, skipping');
    return;
  }

  const baseURL = process.env.SEARXNG_URL || 'http://127.0.0.1:8080';

  const provider = {
    id: 'searxng',

    available() { return true; },

    async search(request, signal) {
      const { query, maxResults } = request;
      const params = new URLSearchParams({
        q: query,
        format: 'json',
        language: 'zh-CN',
        pageno: '1',
      });

      const url = `${baseURL}/search?${params}`;

      try {
        const { stdout } = await execFileAsync('curl', [
          '-s', url, '--max-time', '15',
        ], { timeout: 20000 });

        const data = JSON.parse(stdout);

        // SearXNG JSON API: regular hits in `results[]`, wikipedia-engine
        // standard-article hits in `infoboxes[]` (shape: {infobox, id, content, urls}).
        // Merge both so wikipedia articles are not silently dropped.
        const merged = [
          ...(data.results || []),
          ...(data.infoboxes || []).map(ib => ({
            url: ib.id || (ib.urls && ib.urls[0] && ib.urls[0].url) || '',
            title: ib.infobox || undefined,
            content: ib.content || undefined,
          })),
        ];

        const results = merged.slice(0, maxResults || 10);

        const sources = results.map(r => ({
          url: r.url || '',
          title: r.title || undefined,
          snippet: r.content || undefined,
        }));

        // SearXNG doesn't provide an "answer" but we can use the first result's content
        return {
          sources,
          truncated: merged.length > (maxResults || 10),
        };
      } catch (err) {
        throw new Error(`SearXNG search failed: ${err.message}`);
      }
    },
  };

  // NOTE: do NOT pass the returned disposer to ctx.effect(dispose).
  // ctx.effect(fn) executes fn immediately and collects fn's RETURN value as
  // the teardown — passing the disposer invokes it right away and unregisters
  // the provider instantly. The registration is already scoped to the calling
  // fiber by registerSearchProvider, so nothing else is needed here.
  ctx.web.registerSearchProvider(provider);

  console.error('[searxng] registered (local ' + baseURL + ')');
}
