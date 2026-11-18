import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash,randomBytes} from 'node:crypto';
const file=new URL('./site/_worker.js',import.meta.url);
const source=await readFile(file,'utf8');
const {default:worker}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
const pass='A-very-strong-test-only-password_2026';
const env={
 CRM_AUTH_PASSWORD:pass,
 ASSETS:{fetch:async r=>new Response('TEST-PRIVATE-ASSET:'+new URL(r.url).pathname,{headers:{'Content-Type':'text/plain','Access-Control-Allow-Origin':'*'}})}
};
const get=(path,more={})=>worker.fetch(new Request('https://crm.example.test'+path,more),env);
const form=(username,password)=>worker.fetch(new Request('https://crm.example.test/_auth/login',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded','Origin':'https://crm.example.test'},body:new URLSearchParams({username,password})}),env);
let res=await get('/crm-data.json');
assert.equal(res.status,401);
assert.equal((await res.text()).includes('TEST-PRIVATE'),false);
res=await get('/');
assert.equal(res.status,200);
assert.ok((await res.text()).includes('petr@bohanes-technologies.cz'));
res=await get('/index.html');
assert.equal(res.status,200);
res=await get('/manifest.webmanifest');
assert.equal(res.status,200);
res=await get('/_auth/login');
assert.equal(res.status,200);
res=await worker.fetch(new Request('https://crm.example.test/_auth/login',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded','Origin':'null'},body:new URLSearchParams({username:'petr@bohanes-technologies.cz',password:'badpass123'})}),env);
assert.equal(res.status,401);
res=await form('petr@bohanes-technologies.cz','wrong-password');
assert.equal(res.status,401);
res=await form('petr@bohanes-technologies.cz',pass);
assert.equal(res.status,303);
const cookie=res.headers.get('set-cookie').split(';')[0];
assert.ok(cookie.startsWith('bohanes_crm_session='));
for(const p of ['/','/index.html','/crm-data.json','/crm-data.js','/spa-directory.json','/regions.json']){
 res=await get(p,{headers:{Cookie:cookie}});
 assert.equal(res.status,200,p);
 assert.ok((await res.text()).startsWith('TEST-PRIVATE-ASSET:'),p);
 assert.equal(res.headers.get('access-control-allow-origin'),null);
 assert.ok((res.headers.get('cache-control')||'').includes('no-store'));
}
res=await get('/crm-data.json',{headers:{Cookie:cookie.replace('=', '=M')}});
assert.equal(res.status,401);
res=await worker.fetch(new Request('https://crm.example.test/_auth/logout',{method:'POST',headers:{Cookie:cookie}}),env);
assert.equal(res.status,303);
assert.ok(res.headers.get('set-cookie').includes('Max-Age=0'));
const prev=env.CRM_AUTH_PASSWORD;
env.CRM_AUTH_PASSWORD='another-strong-replacement-password';
res=await get('/',{headers:{Cookie:cookie}});
assert.equal(res.status,200);
assert.ok((await res.text()).includes('Přihlášení'));
env.CRM_AUTH_PASSWORD=prev;
res=await get('/',{headers:{Cookie:cookie}});
assert.equal(res.status,200);
assert.ok((await res.text()).startsWith('TEST-PRIVATE-ASSET'));
console.log('AUTH TEST PASS: no bypass, valid login, cookie, logout, password rotation, PWA manifest, private asset gating');
