document.body.classList.add('nav-hidden');
function lkV31Polish(){
  document.querySelectorAll('.full').forEach(function(el){
    el.innerHTML = el.innerHTML.replace('Pauza poslední procedura → večeře:', 'Čas mezi koncem procedur a večeří:');
  });
}
lkV31Polish();
window.addEventListener('load', lkV31Polish);
setTimeout(lkV31Polish, 200);
setTimeout(function(){ document.body.classList.add('nav-hidden'); lkV31Polish(); }, 900);
