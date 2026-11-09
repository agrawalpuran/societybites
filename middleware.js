// Vercel Edge: kitchen subdomains must expose a slug before Flutter boots.
// Redirect puran.societyeats.com/ → /kitchen/puran (URL stays on same host).
const APEX = 'societyeats.com';
const RESERVED = new Set(['www', 'app', 'api', 'admin']);
const SLUG_RE = /^[a-z0-9](?:[a-z0-9-]{0,28}[a-z0-9])?$/;

function kitchenSlugFromHost(hostHeader) {
  const host = (hostHeader || '').split(':')[0].trim().toLowerCase();
  if (!host || !host.endsWith('.' + APEX)) return null;

  const prefix = host.slice(0, -(APEX.length + 1));
  const leaf = prefix.includes('.') ? prefix.split('.').pop() : prefix;
  if (!leaf || RESERVED.has(leaf)) return null;
  if (!SLUG_RE.test(leaf)) return null;
  return leaf;
}

export default function middleware(request) {
  const slug = kitchenSlugFromHost(request.headers.get('host'));
  if (!slug) return;

  const url = new URL(request.url);
  const path = url.pathname;
  if (path !== '/' && path !== '/index.html') return;

  const target = new URL(request.url);
  target.pathname = `/kitchen/${slug}`;

  const response = Response.redirect(target.toString(), 307);
  response.headers.append(
    'Set-Cookie',
    `se_kitchen_slug=${encodeURIComponent(slug)}; Path=/; Max-Age=86400; SameSite=Lax`,
  );
  return response;
}

export const config = {
  matcher: ['/', '/index.html'],
};
