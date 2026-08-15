(function(){
  'use strict';
  if(!('serviceWorker' in navigator)) return;

  function register(){
    navigator.serviceWorker.register('./sw.js', {
      scope: './',
      updateViaCache: 'none'
    }).then(function(registration){
      registration.update();
      document.addEventListener('visibilitychange', function(){
        if(!document.hidden) registration.update();
      });
    }).catch(function(){});
  }

  window.addEventListener('load', register, { once: true });
})();
