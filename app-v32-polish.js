function lkText(selector){
  var element = document.querySelector(selector);
  return element ? element.textContent.trim().replace(/\s+/g, ' ') : '';
}
function lkUpperSummary(){
  var summary = document.querySelector('.full');
  var current = document.querySelector('.now2');
  if(!summary || !current) return;
  var status = lkText('.now2 .pill');
  var command = lkText('.now2 .cmd');
  var amount = lkText('.now2 .big').replace(/([0-9])([a-zA-Zá-žÁ-Ž])/g, '$1 $2');
  var detailHead = lkText('.now2 .detail span');
  var detailTitle = lkText('.now2 .detail b');
  var isTomorrow = detailHead.indexOf('ne 24. 5.') >= 0 || detailHead.indexOf('zítra') >= 0;
  if(isTomorrow){
    summary.innerHTML = 'Dnešek hotový · další jídlo: <b>' + detailTitle + ' 07:00</b>';
    return;
  }
  if(status === 'VOLNO'){
    summary.innerHTML = command + ': <b>' + amount + '</b>';
    return;
  }
  if(status === 'JE ČAS VYRAZIT'){
    summary.innerHTML = 'Teď vyrazit na další událost: <b>' + detailTitle + '</b>';
    return;
  }
  if(status === 'PROBÍHÁ'){
    summary.innerHTML = 'Právě probíhá: <b>' + detailTitle + '</b>';
    return;
  }
  summary.innerHTML = 'Čas mezi koncem procedur a večeří: <b>' + summary.textContent.split(':').pop().trim() + '</b>';
}
function lkHideNav(){
  document.body.classList.add('nav-hidden');
}
window.addEventListener('scroll', function(){ setTimeout(lkHideNav, 20); }, {passive:true});
window.addEventListener('touchmove', function(){ setTimeout(lkHideNav, 20); }, {passive:true});
window.addEventListener('wheel', function(){ setTimeout(lkHideNav, 20); }, {passive:true});
window.addEventListener('load', function(){ setTimeout(lkHideNav, 100); lkUpperSummary(); });
setTimeout(function(){ lkHideNav(); lkUpperSummary(); }, 150);
setTimeout(function(){ lkHideNav(); lkUpperSummary(); }, 900);
setInterval(lkUpperSummary, 1000);
