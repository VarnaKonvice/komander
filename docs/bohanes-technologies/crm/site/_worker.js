/*
 * Bohanes Technologies CRM — Cloudflare Pages server-side access guard.
 * This runs BEFORE serving any HTML, JSON, JS, pictures or other CRM assets.
 * The credentials are in Cloudflare encrypted environment secrets, never in JS/HTML.
 */
const ACCOUNT_NAME = 'petr@bohanes-technologies.cz';
const COOKIE_NAME = 'bohanes_crm_session';
const SESSION_SECONDS = 7 * 24 * 60 * 60;
const textEncoder = new TextEncoder();

function hexToBytes(hex) {
  if (!/^(?:[0-9a-f]{2})+$/i.test(hex || '')) return null;
  return Uint8Array.from(hex.match(/.{2}/g), value => parseInt(value, 16));
}
function bytesToHex(bytes) {
  return [...bytes].map(value => value.toString(16).padStart(2, '0')).join('');
}
function base64Url(bytes) {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}
function unbase64Url(s) {
  if (!/^[a-zA-Z0-9_-]+$/.test(s || '') || s.length > 200) return null;
  try {
    const raw = atob(s.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - s.length % 4) % 4));
    return Uint8Array.from(raw, c => c.charCodeAt(0));
  } catch {
    return null;
  }
}
function equalsInConstantTime(a, b) {
  if (!a || !b || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}
function secureHeaders(headers = {}) {
  return {
    'Cache-Control': 'private, no-store, max-age=0',
    'Pragma': 'no-cache',
    'X-Robots-Tag': 'noindex, nofollow, noarchive',
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer',
    'X-Frame-Options': 'DENY',
    ...headers
  };
}
function htmlEscape(value) {
  return String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}
function loginHtml(message = '', isError = false) {
  return `<!doctype html>
<html lang="cs"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex,nofollow,noarchive"><meta name="theme-color" content="#15384e">
<title>Přihlášení | Bohanes Technologies CRM</title>
<style>
:root{color-scheme:light}*{box-sizing:border-box}
body{margin:0;min-height:100vh;display:grid;place-items:center;padding:24px;background:linear-gradient(145deg,#eaf3f7,#f5f9fb 48%,#dbecef);color:#143a50;font:16px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
main{width:min(440px,100%);background:#fff;border:1px solid #cfdee6;border-radius:22px;box-shadow:0 16px 52px #173c521c;padding:clamp(24px,6vw,39px)}
small{display:block;text-transform:uppercase;letter-spacing:.12em;font-weight:750;color:#16748b;margin-bottom:7px}h1{margin:0 0 8px;font-size:27px;line-height:1.2}
p{margin:0 0 26px;color:#536e7e}label{display:block;margin-bottom:16px;font-weight:700;font-size:14px}
input{display:block;margin-top:7px;width:100%;padding:13px 14px;border:1px solid #adc3d0;background:#f9fcfd;border-radius:9px;color:#15384e;font:inherit}
input:focus{outline:2px solid #047f92;outline-offset:2px}
button{width:100%;border:0;border-radius:10px;background:#133f5e;color:white;padding:14px;font:inherit;font-weight:700;cursor:pointer}
button:hover{background:#075a73}.feedback{padding:12px;margin:0 0 18px;background:#fff2e9;border-radius:9px;color:#943b12;font-size:14px}
footer{padding-top:20px;font-size:12px;text-align:center;color:#648192}
</style></head><body><main><small>Bohanes Technologies</small><h1>Obchodní CRM</h1>
<p>Soukromý přístup k lázeňským kontaktům a obchodním případům.</p>
${message ? `<div class="feedback" role="alert">${htmlEscape(message)}</div>` : ''}
<form method="post" action="/_auth/login" autocomplete="on">
<label>Uživatelské jméno<input name="username" type="text" autocomplete="username" required maxlength="80" value="${htmlEscape(ACCOUNT_NAME)}"></label>
<label>Heslo<input name="password" type="password" autocomplete="current-password" required maxlength="250" autofocus></label>
<button type="submit">Přihlásit se</button></form>
<footer>Chráněný přístup · data jsou dostupná pouze po přihlášení</footer>
</main></body></html>`;
}
function page(message, status = 200) {
  return new Response(loginHtml(message, status !== 200), {
    status,
    headers: secureHeaders({
      'Content-Type': 'text/html; charset=utf-8',
      'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'"
    })
  });
}
async function validPassword(password, expected) {
  if (typeof password !== 'string' || typeof expected !== 'string' || password.length > 250 || expected.length < 8) return false;
  const actualDigest = new Uint8Array(await crypto.subtle.digest('SHA-256', textEncoder.encode(password)));
  const expectedDigest = new Uint8Array(await crypto.subtle.digest('SHA-256', textEncoder.encode(expected)));
  return equalsInConstantTime(actualDigest, expectedDigest);
}
async function sessionKey(env) {
  if (!env.CRM_AUTH_PASSWORD || env.CRM_AUTH_PASSWORD.length < 8) return null;
  const secret = await crypto.subtle.digest('SHA-256', textEncoder.encode('bohanes-crm-session-v1:' + env.CRM_AUTH_PASSWORD));
  return crypto.subtle.importKey('raw', secret, {name:'HMAC',hash:'SHA-256'}, false, ['sign','verify']);
}
async function signSession(env) {
  const key = await sessionKey(env);
  if (!key) return null;
  const expires = Math.floor(Date.now()/1000) + SESSION_SECONDS;
  const nonce = base64Url(crypto.getRandomValues(new Uint8Array(16)));
  const body = expires + '.' + nonce;
  const signed = body + '.' + ACCOUNT_NAME;
  const signature = new Uint8Array(await crypto.subtle.sign('HMAC', key, textEncoder.encode(signed)));
  return body + '.' + base64Url(signature);
}
async function sessionValid(request, env) {
  const key = await sessionKey(env);
  if (!key || !env.CRM_AUTH_PASSWORD) return false;
  const cookies = request.headers.get('Cookie') || '';
  const token = cookies.split(';').map(s => s.trim()).find(s => s.startsWith(COOKIE_NAME+'='));
  if (!token) return false;
  const parts = token.slice(COOKIE_NAME.length+1).split('.');
  if (parts.length !== 3 || !/^\d{10}$/.test(parts[0]) || !/^[\w-]{22}$/.test(parts[1])) return false;
  const expiry = Number(parts[0]), now = Math.floor(Date.now()/1000);
  if (expiry <= now || expiry > now + SESSION_SECONDS) return false;
  const signature = unbase64Url(parts[2]);
  if (!signature || signature.length !== 32) return false;
  const message = parts[0] + '.' + parts[1] + '.' + ACCOUNT_NAME;
  return crypto.subtle.verify('HMAC', key, signature, textEncoder.encode(message));
}
function noStoreAssets(response) {
  const headers = new Headers(response.headers);
  for (const [key, value] of Object.entries(secureHeaders())) headers.set(key,value);
  headers.set('Vary', 'Cookie');
  headers.delete('Access-Control-Allow-Origin');
  return new Response(response.body, {status:response.status,statusText:response.statusText,headers});
}
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    const configured = typeof env.CRM_AUTH_PASSWORD === 'string' && env.CRM_AUTH_PASSWORD.length >= 8;
    if (!configured) {
      return new Response('CRM je dočasně uzamčeno. Přístup ještě nebyl nakonfigurován.', {
        status:503,headers:secureHeaders({'Content-Type':'text/plain; charset=utf-8'})
      });
    }
    // Icons needed by iOS when installing a PWA never contain personal or CRM data.
    if (request.method === 'GET' && /^(?:\/apple-touch-icon\.png|\/icon-(?:192|512)\.png|\/favicon-final\.svg|\/manifest\.webmanifest)$/.test(path)) {
      return noStoreAssets(await env.ASSETS.fetch(request));
    }
    if (path === '/_auth/login' && request.method === 'POST') {
      // Authentication requires the correct username and password; Origin may be null or rewritten by browsers/proxies.
      if (Number(request.headers.get('Content-Length') || 0)>3200) return page('Příliš dlouhé údaje.',413);
      const type = request.headers.get('Content-Type') || '';
      if (!type.startsWith('application/x-www-form-urlencoded')) return page('Neplatný požadavek.',415);
      let form;
      try {form = await request.formData();} catch {return page('Neplatný formulář.',400);}
      const username=form.get('username'),password=form.get('password');
      if (typeof username === 'string' && username.trim() === ACCOUNT_NAME && await validPassword(password,env.CRM_AUTH_PASSWORD)) {
        const session=await signSession(env);
        if (!session) return page('Přihlášení teď není dostupné.',503);
        return new Response(null,{status:303,headers:secureHeaders({
          'Location':'/',
          'Set-Cookie': COOKIE_NAME+'='+session+'; Max-Age='+SESSION_SECONDS+'; Path=/; Secure; HttpOnly; SameSite=Lax'
        })});
      }
      return page('Nesprávné přihlašovací údaje.',401);
    }
    if (path === '/_auth/logout' && request.method === 'POST') {
      return new Response(null,{status:303,headers:secureHeaders({
        'Location':'/',
        'Set-Cookie': COOKIE_NAME+'=; Max-Age=0; Path=/; Secure; HttpOnly; SameSite=Lax'
      })});
    }
    if (request.method === 'GET' && path === '/_auth/login') return page();
    if (path.startsWith('/_auth/')) return new Response('Nenalezeno',{status:404,headers:secureHeaders()});
    if (!(await sessionValid(request,env))) {
      if (request.method === 'GET' && (path === '/' || path === '/index.html' || path === '/_auth/login')) return page();
      // Don't leak CRM data files or reveal their content for unauthenticated requests.
      return new Response('Přihlášení je vyžadováno.',{
        status:401,
        headers:secureHeaders({'Content-Type':'text/plain; charset=utf-8','WWW-Authenticate':'Session realm="Bohanes CRM"'})
      });
    }
    return noStoreAssets(await env.ASSETS.fetch(request));
  }
};
