// Bohanes Technologies: locked-down placeholder until explicit launch approval.
// All previously deployed product paths must be inaccessible, including cached static paths.
const securityHeaders = {
  'X-Robots-Tag': 'noindex, nofollow, noarchive',
  'Cache-Control': 'no-store, max-age=0, must-revalidate',
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
};
export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname;
    if ((request.method === 'GET' || request.method === 'HEAD') &&
        (path === '/' || path === '/index.html')) {
      const baseUrl = new URL(request.url);
      baseUrl.pathname = '/';
      baseUrl.search = '';
      const asset = await env.ASSETS.fetch(new Request(baseUrl.toString(), request));
      const headers = new Headers(asset.headers);
      for (const [key, value] of Object.entries(securityHeaders)) headers.set(key, value);
      return new Response(asset.body, {status: asset.status, headers});
    }
    return new Response('Nenalezeno.', {status: 404,
      headers: {...securityHeaders, 'Content-Type': 'text/plain; charset=utf-8'}});
  },
};
