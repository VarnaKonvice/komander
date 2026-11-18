/* Historical links into the removed corporate sections now lead to their new pages. */
(() => {
 const destinations = {'#o-nas':'/o-nas.html','#pro-lazne':'/pro-lazne.html'};
 const isOldLanding = /^\/(?:index\.html|podrobnosti\.html)?$/.test(location.pathname);
 if(isOldLanding && Object.prototype.hasOwnProperty.call(destinations,location.hash)){
  location.replace(destinations[location.hash]);
 }
})();

/* Business-facing consumer intro; no external requests and no synthetic app images. */
(() => {
  'use strict';
  const screenMap = {
    today: {
      image: '/screens/commander-today.png?v=20261013-demo',
      alt: 'Skutečná obrazovka Dnes v Lázeňském Commanderu',
      title: 'Ještě čas na kávu?',
      description: '„Volno do večeře“ ukáže prostor na zákusek, procházku nebo chvíli jen pro sebe.'
    },
    week: {
      image: '/screens/commander-week.png?v=20261013-demo',
      alt: 'Skutečná obrazovka Týden v Lázeňském Commanderu',
      title: 'Jak vypadá celý můj týden?',
      description: 'Procedury a přehled volna po jednotlivých dnech.'
    },
    stay: {
      image: '/screens/commander-stay.png?v=20261013-demo',
      alt: 'Skutečná obrazovka Pobyt v Lázeňském Commanderu',
      title: 'Kde najdu informace o pobytu?',
      description: 'Přehled pobytu a jeho procedur na jednom místě.'
    }
  };
  const image = document.getElementById('b2c-screen-image');
  const title = document.getElementById('b2c-screen-title');
  const detail = document.getElementById('b2c-screen-description');
  const buttons = [...document.querySelectorAll('button[data-b2c-screen]')];
  for (const button of buttons) {
    button.addEventListener('click', () => {
      const content = screenMap[button.dataset.b2cScreen];
      if (!content || !image || !title || !detail) return;
      image.src = content.image;
      image.alt = content.alt;
      title.textContent = content.title;
      detail.textContent = content.description;
      for (const b of buttons) {
        const active = b === button;
        b.classList.toggle('is-selected', active);
        b.setAttribute('aria-pressed', active ? 'true' : 'false');
      }
    });
  }
})();


/* One navigation system for the customer page, practical guide and details. */
(() => {
  const menu = document.querySelector('.menu-toggle');
  const nav = document.getElementById('navlinks');
  const header = document.querySelector('header');
  const closeMenu = () => { menu?.setAttribute('aria-expanded', 'false'); nav?.classList.remove('is-open'); };
  menu?.addEventListener('click', () => {
    const open = menu.getAttribute('aria-expanded') !== 'true';
    menu.setAttribute('aria-expanded', String(open));
    nav?.classList.toggle('is-open', open);
  });
  nav?.querySelectorAll('a').forEach(a => a.addEventListener('click', closeMenu));
  document.addEventListener('click', e => { if (!header?.contains(e.target)) closeMenu(); });
  document.addEventListener('keydown', e => { if (e.key === 'Escape') { const wasOpen = menu?.getAttribute('aria-expanded') === 'true'; closeMenu(); if (wasOpen) menu.focus(); } });
  addEventListener('resize', () => { if (innerWidth >= 1241) closeMenu(); });
  const page = document.body.dataset.page;
  const localSectionKeys = {domu:'home','rychly-nahled':'preview','rychla-cena':'price',instalace:'install','o-nas':'about','pro-lazne':'business',kontakt:'contact'};
  const observed = page === 'home' ? [...document.querySelectorAll('main [id]')].filter(s => localSectionKeys[s.id]) : [];
  const update = () => {
    let key = page;
    for (const s of observed) if (s.getBoundingClientRect().top <= (header?.offsetHeight || 76) + 80) key = localSectionKeys[s.id];
    for (const a of document.querySelectorAll('[data-nav-key]')) {
      const active = a.dataset.navKey === key;
      a.classList.toggle('active', active);
      if (active) a.setAttribute('aria-current', key === page ? 'page' : 'location'); else a.removeAttribute('aria-current');
    }
  };
  addEventListener('scroll', update, {passive:true}); update();
  // Preserve incoming anchors and browser Back instead of overwriting URLs during scrolling.
  if ('scrollRestoration' in history) history.scrollRestoration = 'auto';
  if (page === 'details' && new URLSearchParams(location.search).get('platform') === 'android') document.querySelector('#application-android-tab')?.click();
})();

// Local-only safe-area check; normal pages always use the device's env() insets.
if (['localhost','127.0.0.1'].includes(location.hostname) && new URLSearchParams(location.search).get('safe-area-test') === 'iphone-landscape') {
 document.documentElement.style.setProperty('--test-safe-left','59px');
 document.documentElement.style.setProperty('--test-safe-right','59px');
}


/* Keep a product section selector visible while exploring the detail page. */
(() => {
 const bar=document.querySelector('.commander-subnav');
 if(!bar)return;
 const picker=bar.querySelector('select');
 const links=[...bar.querySelectorAll('[data-product-section]')];
 const sections=links.map(a=>document.getElementById(a.dataset.productSection)).filter(Boolean);
 picker?.addEventListener('change',()=>{const target=document.getElementById(picker.value.slice(1));if(!target)return;if(location.hash!==picker.value)history.pushState(null,'',location.pathname+location.search+picker.value);target.scrollIntoView({behavior:'auto',block:'start'});update();});
 const update=()=>{
  let active='podrobnosti';
  const edge=(document.querySelector('header')?.offsetHeight||88)+bar.offsetHeight+45;
  for(const section of sections)if(section.getBoundingClientRect().top<=edge)active=section.id;
  for(const link of links){const selected=link.dataset.productSection===active;link.classList.toggle('active',selected);if(selected)link.setAttribute('aria-current','location');else link.removeAttribute('aria-current');}
  if(picker)picker.value='#'+active;
 };
 addEventListener('scroll',update,{passive:true});addEventListener('resize',update);addEventListener('hashchange',update);update();
})();


// An explicit anchor wins over a stale restored position when this document is refreshed.
if (performance.getEntriesByType('navigation')[0]?.type === 'reload' && location.hash) {
 addEventListener('load', () => {
  const anchor = document.getElementById(decodeURIComponent(location.hash.slice(1)));
  anchor?.scrollIntoView({behavior:'auto', block:'start'});
 }, {once:true});
}


/* Enlarge the intact anonymized sheet together with its fictitious web labels. */
document.querySelector('[data-paper-enlarge]')?.addEventListener('click', () => {
 const dialog = document.getElementById('imageDialog');
 const paper = document.querySelector('.journey-paper-sample .paper-document');
 const detail = document.getElementById('calendarDetail');
 if (!dialog || !paper || !detail) return;
 document.getElementById('imageTitle').textContent = 'Rozpis z Darkova · fiktivní identifikační údaje';
 document.getElementById('imageDetail').hidden = true;
 document.getElementById('originalImageRow').hidden = true;
 detail.hidden = false;
 detail.replaceChildren(paper.cloneNode(true));
 dialog.showModal();
});

// Measure the rendered header including its border for precise sticky offsets.
(() => {
 const header = document.querySelector('header.unified-header');
 if (!header) return;
 const measure = () => document.body.style.setProperty('--header-height', `${header.getBoundingClientRect().height}px`);
 new ResizeObserver(measure).observe(header);
 measure();
})();


/* Visitor-initiated mailto contact. No server-side collection or automatic send. */
(() => {
  document.querySelectorAll('form[data-contact-draft]').forEach(form => {
    const status = form.querySelector('.bt-contact-feedback');
    form.addEventListener('submit', event => {
      event.preventDefault();
      if (!form.reportValidity()) return;
      const data = new FormData(form);
      const message = [
        'Jméno: ' + String(data.get('name') || '').trim(),
        'Firma / lázně: ' + String(data.get('organization') || '').trim(),
        'Pozice: ' + String(data.get('position') || '').trim(),
        'E-mail: ' + String(data.get('email') || '').trim(),
        'Telefon: ' + String(data.get('phone') || '').trim(),
        '',
        String(data.get('message') || '').trim()
      ].join('\n');
      const mailto = 'mailto:podpora@bohanes-technologies.cz'
        + '?subject=' + encodeURIComponent('Dotaz z webu Bohanes Technologies')
        + '&body=' + encodeURIComponent(message);
      status.textContent = 'Otevírá se e-mailová aplikace. Zpráva nebude odeslána, dokud ji sami nepotvrdíte.';
      status.dataset.state = 'success';
      window.location.href = mailto;
    });
  });
})();


/* Spa partner CTA pre-populates the contact form without sending user data. */
(() => {
  document.querySelectorAll('[data-contact-topic]').forEach(link => {
    link.addEventListener('click', () => {
      const form = document.querySelector('#kontakt [data-contact-draft]');
      const box = form?.querySelector('textarea[name="message"]');
      if (box && !box.value.trim()) box.value = link.dataset.contactTopic || '';
    });
  });
})();


/* Shared topic handoff from Pro lázně to the contact form (no data transfer). */
(() => {
 const requestedTopic = new URLSearchParams(location.search).get('tema');
 if (requestedTopic !== 'spoluprace' || !['/','/index.html'].includes(location.pathname)) return;
 const field = document.querySelector('#kontakt [data-contact-draft] textarea[name="message"]');
 if (field && !field.value.trim()) {
   field.value = 'Rád(a) bych probral(a) možnost využití Lázeňského Commanderu pro naše lázeňské zařízení. Prosím o informace k pilotní spolupráci.';
 }
})();
