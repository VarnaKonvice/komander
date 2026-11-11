
const menu=document.querySelector('.menu-toggle');
const nav=document.getElementById('navlinks');
if(menu&&nav){
  menu.addEventListener('click',()=>{
    const open=nav.classList.toggle('is-open');
    menu.setAttribute('aria-expanded',String(open));
  });
  nav.querySelectorAll('a').forEach(a=>a.addEventListener('click',()=>{nav.classList.remove('is-open');menu.setAttribute('aria-expanded','false')}));
}
const dialog=document.getElementById('imageDialog');
const detail=document.getElementById('imageDetail');
const title=document.getElementById('imageTitle');
const original=document.getElementById('originalImage');
const originalRow=document.getElementById('originalImageRow');
const calendarDetail=document.getElementById('calendarDetail');
document.querySelectorAll('[data-enlarge]').forEach(button=>button.addEventListener('click',()=>{
  const img=button.querySelector('img'); if(!img||!dialog)return;
  if(calendarDetail){calendarDetail.hidden=true;calendarDetail.replaceChildren();}
  if(detail){detail.hidden=false;detail.src=img.src;detail.alt=img.alt||'';}
  if(title) title.textContent=img.alt||'Obrazovka Commanderu';
  if(original){original.href=img.src; originalRow.hidden=false;}
  dialog.showModal();
}));
document.querySelectorAll('[data-enlarge-calendar]').forEach(button=>button.addEventListener('click',()=>{
  const card=button.closest('.calendar-platform'); if(!card||!dialog||!calendarDetail)return;
  const clone=card.cloneNode(true); clone.querySelectorAll('[data-enlarge-calendar]').forEach(el=>el.remove());
  if(detail){detail.hidden=true;detail.removeAttribute('src');}
  if(originalRow)originalRow.hidden=true;
  calendarDetail.hidden=false;calendarDetail.replaceChildren(clone);
  if(title)title.textContent=card.querySelector('h3')?.textContent||'Kalendář';
  dialog.showModal();
}));
document.querySelector('.lightbox-close')?.addEventListener('click',()=>dialog?.close());
dialog?.addEventListener('click',e=>{if(e.target===dialog)dialog.close()});
document.getElementById('contactForm')?.addEventListener('submit',e=>e.preventDefault());
