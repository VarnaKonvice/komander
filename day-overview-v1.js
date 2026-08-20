(function(){
  'use strict';

  var PLANNING_FREE_MINUTES = 60;
  var selectedDay = null;
  var lastTab = null;
  var lastUiState = '';
  var lastStaticState = '';
  var busy = false;
  var swipeStart = null;

  function pad(n){ return String(n).padStart(2, '0'); }
  function todayIso(){
    var d = new Date();
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
  }
  function addDaysIso(base, days){
    var d = new Date(base + 'T12:00:00');
    d.setDate(d.getDate() + days);
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
  }
  function dateLabel(iso){
    return new Intl.DateTimeFormat('cs-CZ', { weekday: 'long', day: 'numeric', month: 'numeric' })
      .format(new Date(iso + 'T12:00:00'));
  }
  function escapeHtml(value){
    return String(value == null ? '' : value).replace(/[&<>"']/g, function(c){
      return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c];
    });
  }
  function timeToMinutes(time){
    var m = String(time || '00:00').match(/^(\d{1,2}):(\d{2})/);
    return m ? Number(m[1]) * 60 + Number(m[2]) : 0;
  }
  function minutesToTime(minutes){
    minutes = Math.max(0, Math.min(1439, Math.round(minutes)));
    return pad(Math.floor(minutes / 60)) + ':' + pad(minutes % 60);
  }
  function durationLabel(minutes){
    minutes = Math.max(0, Math.round(minutes));
    if(minutes < 60) return minutes + ' min';
    var hours = Math.floor(minutes / 60);
    var rest = minutes % 60;
    return rest ? hours + ' h ' + rest + ' min' : hours + ' h';
  }
  function procedureWord(count){
    if(count === 1) return 'procedura';
    if(count >= 2 && count <= 4) return 'procedury';
    return 'procedur';
  }
  function itemWord(count){
    if(count === 1) return 'položka';
    if(count >= 2 && count <= 4) return 'položky';
    return 'položek';
  }
  function currentMinute(){
    var d = new Date();
    return d.getHours() * 60 + d.getMinutes();
  }
  function itemStart(item){ return timeToMinutes(item.start); }
  function itemEnd(item){ return Math.max(itemStart(item), timeToMinutes(item.end || item.start)); }
  function itemKindLabel(item){ return item.type === 'meal' ? 'jídlo' : 'procedura'; }
  function itemIcon(item){ return item.type === 'meal' ? '♨︎' : '⌖'; }
  function itemShortLabel(item){
    if(item.type !== 'meal') return item.title;
    if(/snídan/i.test(item.title)) return 'snídaně';
    if(/oběd/i.test(item.title)) return 'oběda';
    if(/večeř/i.test(item.title)) return 'večeře';
    return item.title;
  }
  function isDinner(item){ return item.type === 'meal' && /večeř/i.test(item.title); }

  function readData(){
    var stored = null;
    try{
      if(!window.LazenskySchedule || !window.LazenskySchedule.getSchedule || !window.LazenskySchedule.toLegacySchedule) return null;
      var schedule = window.LazenskySchedule.getSchedule();
      if(!schedule) return null;
      stored = window.LazenskySchedule.toLegacySchedule(schedule);
    }catch(e){ return null; }
    if(!stored || !Array.isArray(stored.items)) return null;
    var items = stored.items.map(function(item, index){
      return {
        id: item.id || 'lk-' + index,
        type: item.type === 'meal' ? 'meal' : 'procedure',
        date: String(item.date || ''),
        start: String(item.start || ''),
        end: String(item.end || item.start || ''),
        title: String(item.title || item.name || 'Událost'),
        place: String(item.place || item.location || '')
      };
    }).filter(function(item){ return item.date && item.start; })
      .sort(function(a, b){ return (a.date + a.start + a.end).localeCompare(b.date + b.start + b.end); });
    return { stay: stored.stay || {}, items: items };
  }
  function dates(data){ return Array.from(new Set(data.items.map(function(item){ return item.date; }))).sort(); }
  function activeTab(){
    var active = document.querySelector('nav [data-tab].active');
    return active ? active.dataset.tab : '';
  }
  function defaultDay(allDates, tab){
    var today = todayIso();
    var tomorrow = addDaysIso(today, 1);
    if(tab === 'tomorrow'){
      if(allDates.indexOf(tomorrow) >= 0) return tomorrow;
      return allDates.find(function(day){ return day > today; }) || allDates[1] || allDates[0];
    }
    if(allDates.indexOf(today) >= 0) return today;
    return allDates.find(function(day){ return day > today; }) || allDates[0];
  }
  function dayItems(data, day){
    return data.items.filter(function(item){ return item.date === day; })
      .sort(function(a, b){ return itemStart(a) - itemStart(b) || itemEnd(a) - itemEnd(b); });
  }

  // Overlapping obligations become one occupied block and never create false free time.
  function freeWindows(items, refMinute, isToday){
    var result = [];
    var clusterEnd = null;
    items.forEach(function(item){
      var start = itemStart(item);
      var end = itemEnd(item);
      if(clusterEnd == null){ clusterEnd = end; return; }
      if(start > clusterEnd){
        var shownStart = isToday ? Math.max(clusterEnd, refMinute) : clusterEnd;
        if(start > shownStart) result.push({ start: shownStart, end: start, before: item });
        clusterEnd = end;
        return;
      }
      clusterEnd = Math.max(clusterEnd, end);
    });
    return result.filter(function(window){ return !isToday || window.end > refMinute; });
  }

  function buildSummary(items, day){
    var today = todayIso();
    var isToday = day === today;
    var isPast = day < today;
    var reference = isToday ? currentMinute() : 0;
    var procedures = items.filter(function(item){ return item.type === 'procedure'; });
    var meals = items.filter(function(item){ return item.type === 'meal'; });
    var remainingProcedures = procedures.filter(function(item){ return !isToday || itemEnd(item) > reference; });
    var current = isToday ? items.find(function(item){
      return itemStart(item) <= reference && itemEnd(item) > reference;
    }) : null;
    var next = isPast ? null : items.find(function(item){ return itemStart(item) > reference; });
    var previous = isToday ? items.filter(function(item){ return itemEnd(item) <= reference; }).pop() : null;
    var lastProcedure = procedures.reduce(function(best, item){
      return !best || itemEnd(item) > itemEnd(best) ? item : best;
    }, null);
    var free = freeWindows(items, 0, false);
    var meaningfulFree = free.filter(function(window){ return window.end - window.start >= PLANNING_FREE_MINUTES; });
    var upcomingDinner = meals.find(function(item){
      return isDinner(item) && (!isToday || itemStart(item) > reference);
    });
    var freeToDinner = upcomingDinner && meaningfulFree.find(function(window){ return window.before.id === upcomingDinner.id; });

    return {
      isToday: isToday,
      isPast: isPast,
      reference: reference,
      procedures: procedures,
      remainingProcedures: remainingProcedures,
      current: current,
      next: next,
      previous: previous,
      lastProcedure: lastProcedure,
      hasUpcomingItem: !isPast && items.some(function(item){ return itemEnd(item) > reference; }),
      meaningfulFree: meaningfulFree,
      freeToDinner: freeToDinner
    };
  }

  function renderProcedureFact(summary){
    if(summary.isToday && !summary.hasUpcomingItem) return '';
    if(!summary.procedures.length){
      return '<div class="lkDayMetric lkFactNone"><i class="lkBadge">Procedury</i><b>' +
        (summary.isToday ? 'Dnes bez procedur' : 'Bez procedur') + '</b></div>';
    }
    if(summary.isToday && !summary.remainingProcedures.length){
      return '<div class="lkDayMetric lkFactProc"><i class="lkBadge">Procedury</i><b>Procedury pro dnešek hotové</b><small>' +
        '<span>Poslední skončila ' + escapeHtml(summary.lastProcedure.end) + '</span></small></div>';
    }
    var relevantProcedures = summary.isToday ? summary.remainingProcedures : summary.procedures;
    var count = relevantProcedures.length;
    var lastRelevantProcedure = relevantProcedures[relevantProcedures.length - 1];
    var timeSummary = relevantProcedures.length === 1
      ? escapeHtml(relevantProcedures[0].start) + '-' + escapeHtml(relevantProcedures[0].end)
      : '<span>' + (summary.isToday ? 'Další ' : 'První ') + escapeHtml(relevantProcedures[0].start) +
        '</span><span>Poslední ' + escapeHtml(lastRelevantProcedure.end) + '</span>';
    return '<div class="lkDayMetric lkFactProc"><i class="lkBadge">Procedury</i><b>' +
      (summary.isToday ? 'Ještě ' : '') + count + ' ' + procedureWord(count) + '</b><small>' + timeSummary + '</small></div>';
  }
  function renderFreeFact(summary){
    if(summary.isToday && !summary.hasUpcomingItem) return '';
    var window = summary.freeToDinner || summary.meaningfulFree.reduce(function(longest, candidate){
      return !longest || candidate.end - candidate.start > longest.end - longest.start ? candidate : longest;
    }, null);
    if(!window){
      return '<div class="lkDayMetric lkFactNoFree"><i class="lkBadge">Volno</i><b>Bez delšího volna</b></div>';
    }
    return '<div class="lkDayMetric lkFactFree"><i class="lkBadge">Volno</i><b>' +
      durationLabel(window.end - window.start) + '</b><small>' + minutesToTime(window.start) + '-' +
      minutesToTime(window.end) + (summary.freeToDinner ? '' : ' · do ' + escapeHtml(window.before.title)) + '</small></div>';
  }
  function nextProcedureAfter(data, day){
    var reference = day === todayIso() ? currentMinute() : 0;
    return data.items.find(function(item){
      return item.type === 'procedure' && (item.date > day || (item.date === day && itemStart(item) > reference));
    }) || null;
  }
  function nextProcedureLabel(item){
    var tomorrow = addDaysIso(todayIso(), 1);
    var when = item.date === tomorrow ? 'zítra' : dateLabel(item.date);
    return when + ' ' + item.start + ' · ' + item.title;
  }
  function renderNextProcedureCard(summary, data, day){
    if(!summary.isToday || !summary.procedures.length || summary.remainingProcedures.length) return '';
    var item = nextProcedureAfter(data, day);
    if(!item) return '';
    var tomorrow = addDaysIso(todayIso(), 1);
    var when = item.date === tomorrow ? 'zítra' : dateLabel(item.date);
    return '<section class="lkNext lkNextProcedureCard"><div class="lkNextTop"><span>Další procedura</span><i class="lkBadge">Procedury</i></div>' +
      '<b><strong>' + escapeHtml(when) + '</strong><em> ' + escapeHtml(item.start) + '</em></b><div class="lkNextTitle">' +
      escapeHtml(item.title) + '</div><small><mark>' + itemIcon(item) + '</mark>' + escapeHtml(item.place || 'Místo bude upřesněno') +
      '</small></section>';
  }
  function liveState(data, now){
    if(!window.LazenskySchedule || !window.LazenskySchedule.computeLiveState) return null;
    try{
      var schedule = window.LazenskySchedule.getSchedule ? window.LazenskySchedule.getSchedule() : null;
      return window.LazenskySchedule.computeLiveState(schedule || data, now || new Date());
    }catch(e){ return null; }
  }
  function liveClock(iso){ return iso ? iso.slice(11, 16) : ''; }
  function liveKind(event){ return event && event.kind === 'meal' ? 'meal' : 'procedure'; }
  function liveIcon(event){ return liveKind(event) === 'meal' ? '♨︎' : '⌖'; }
  function liveCountdown(minutes){ return durationLabel(Math.max(0, minutes || 0)); }
  function renderLiveCard(data, day){
    if(day !== todayIso()) return '';
    var live = liveState(data);
    if(!live || live.state === 'NO_SCHEDULE') return '';
    if(live.state === 'UPCOMING'){
      return '<section class="lkNext lkLiveBlock lkLiveUpcoming ' + liveKind(live.event) + '" data-lk-live-state="UPCOMING"><div class="lkNextTop"><span>Live · následuje</span><i class="lkBadge">' +
        escapeHtml(liveKind(live.event) === 'meal' ? 'Jídlo' : 'Procedura') + '</i></div><b><strong>' + escapeHtml(liveClock(live.startAt)) +
        '</strong></b><div class="lkNextTitle">' + escapeHtml(live.event.title) + '</div><small><mark>' + liveIcon(live.event) + '</mark>' +
        '<span class="lkLiveLocation">' + escapeHtml(live.event.location || 'Místo bude upřesněno') + '</span></small><p>Vyrazit v ' + escapeHtml(liveClock(live.leaveAt)) + '</p><p class="lkLiveCountdown" data-lk-live-countdown="1">Vyrazit za ' +
        escapeHtml(liveCountdown(live.minutesUntilLeave)) + '</p></section>';
    }
    if(live.state === 'LEAVE_NOW'){
      return '<section class="lkNext lkLiveBlock lkLiveLeave" data-lk-live-state="LEAVE_NOW"><div class="lkNextTop"><span>VYRAZIT TEĎ</span><i class="lkBadge">Live</i></div><b><strong>' +
        escapeHtml(liveClock(live.startAt)) + '</strong></b><div class="lkNextTitle">' + escapeHtml(live.event.title) + '</div><small><mark>' +
        liveIcon(live.event) + '</mark><span class="lkLiveLocation">' + escapeHtml(live.event.location || 'Místo bude upřesněno') + '</span></small></section>';
    }
    if(live.state === 'IN_PROGRESS'){
      return '<section class="lkNext lkLiveBlock lkLiveProgress ' + liveKind(live.event) + '" data-lk-live-state="IN_PROGRESS"><div class="lkNextTop"><span>PRÁVĚ PROBÍHÁ</span><i class="lkBadge">Live</i></div><b><strong>' +
        escapeHtml(liveClock(live.endAt)) + '</strong><em> konec</em></b><div class="lkNextTitle">' + escapeHtml(live.event.title) + '</div><small><mark>' +
        liveIcon(live.event) + '</mark><span class="lkLiveLocation">' + escapeHtml(live.event.location || 'Místo bude upřesněno') + '</span></small></section>';
    }
    var next = live.nextEvent;
    return '<section class="lkNext lkLiveBlock lkLiveStatus" data-lk-live-state="DAY_DONE"><div class="lkNextTop"><span>DNEŠNÍ PROGRAM HOTOVÝ</span><i class="lkBadge">Live</i></div>' +
      (next ? '<div class="lkNextProcedure"><span>' + (next.date === addDaysIso(todayIso(), 1) ? 'První zítřejší událost' : 'Další událost') + '</span><strong class="lkLiveNextEvent">' + escapeHtml(dateLabel(next.date)) + ' ' + escapeHtml(next.start) + ' · ' + escapeHtml(next.title) +
        '</strong></div>' : '') + '</section>';
  }
  function renderTimelineItem(item, summary){
    var isPast = summary.isToday && itemEnd(item) <= summary.reference;
    var isCurrent = summary.current && summary.current.id === item.id;
    return '<article class="lkTimelineRow lkTileCard ' + item.type + (isPast ? ' isPast' : '') + (isCurrent ? ' isCurrent' : '') +
      '"><div class="lkTimelineMain"><div class="lkTimelineTime"><strong>' + escapeHtml(item.start) +
      '</strong><span> - ' + escapeHtml(item.end) + '</span></div><div class="lkTimelineTitle">' +
      escapeHtml(item.title) + '</div><div class="lkTimelinePlace"><mark>' +
      itemIcon(item) + '</mark>' + escapeHtml(item.place) +
      '</div></div><span class="lkBadge">' + itemKindLabel(item).toUpperCase() + '</span></article>';
  }
  function renderProgramTimeline(items, summary){
    var pastItems = summary.isToday ? items.filter(function(item){ return itemEnd(item) <= summary.reference; }) : [];
    var visibleItems = summary.isToday
      ? items.filter(function(item){ return itemEnd(item) > summary.reference; })
      : items;
    var pastHtml = pastItems.length
      ? '<details class="lkPastProgram"><summary><span>Proběhlo</span><b>· ' + pastItems.length + ' ' + itemWord(pastItems.length) +
        '</b></summary><div class="lkTimeline">' + pastItems.map(function(item){ return renderTimelineItem(item, summary); }).join('') +
        '</div></details>'
      : '';
    var visibleHtml = visibleItems.length
      ? '<div class="lkTimeline">' + visibleItems.map(function(item){ return renderTimelineItem(item, summary); }).join('') + '</div>'
      : '';
    return visibleHtml + pastHtml;
  }

  function overviewStateKey(data, day, tab){
    var items = dayItems(data, day);
    var summary = buildSummary(items, day);
    var schedule = data.items.map(function(item){
      return [item.id, item.date, item.start, item.end, item.title, item.place, item.type].join('~');
    }).join('|');
    var live = tab === 'today' && day === todayIso() ? liveState(data) : null;
    return [tab, day, schedule, summary.current && summary.current.id, summary.next && summary.next.id,
      summary.remainingProcedures.length, summary.hasUpcomingItem ? '1' : '0', live && live.state, live && live.event && live.event.stableId,
      live && live.nextEvent && live.nextEvent.stableId].join('^');
  }
  function scheduleStateKey(data, view){
    return view + '^' + data.items.map(function(item){
      return [item.id, item.date, item.start, item.end, item.title, item.place, item.type].join('~');
    }).join('|');
  }
  function renameNavigation(){
    var overviewButton = document.querySelector('nav [data-tab="week"]');
    if(overviewButton){
      Array.prototype.forEach.call(overviewButton.childNodes, function(node){
        if(node.nodeType === 3) node.nodeValue = 'Přehled';
      });
    }
    var icons = { today: '◷', tomorrow: '▣', week: '▦', stay: '♙', import: '☁' };
    Object.keys(icons).forEach(function(tab){
      var icon = document.querySelector('nav [data-tab="' + tab + '"] .ico');
      if(icon && icon.textContent !== icons[tab]) icon.textContent = icons[tab];
    });
  }
  function renameWeekSummaryLabels(){
    if(activeTab() !== 'week') return;
    var main = document.querySelector('main.content');
    if(main && main.classList) main.classList.add('lkWeekView');
    document.querySelectorAll('.stats .stat span').forEach(function(label){
      if(label.textContent === 'První') label.textContent = 'Program od';
      if(label.textContent === 'Konec') label.textContent = 'Program do';
    });
  }
  function overviewProcedureTile(items){
    var procedures = items.filter(function(item){ return item.type === 'procedure'; });
    if(!procedures.length){
      return '<div class="lkDayMetric lkFactNone"><i class="lkBadge">Procedury</i><b>Bez procedur</b></div>';
    }
    var last = procedures[procedures.length - 1];
    var detail = procedures.length === 1
      ? escapeHtml(procedures[0].start) + '-' + escapeHtml(procedures[0].end)
      : '<span>První ' + escapeHtml(procedures[0].start) + '</span><span>Poslední ' + escapeHtml(last.end) + '</span>';
    return '<div class="lkDayMetric lkFactProc"><i class="lkBadge">Procedury</i><b>' + procedures.length + ' ' +
      procedureWord(procedures.length) + '</b><small>' + detail + '</small></div>';
  }
  function overviewFreeTile(items){
    var free = freeWindows(items, 0, false).filter(function(window){
      return window.end - window.start >= PLANNING_FREE_MINUTES;
    });
    if(!free.length){
      return '<div class="lkDayMetric lkFactNoFree"><i class="lkBadge">Volno</i><b>Bez delšího volna</b></div>';
    }
    var dinner = items.find(isDinner);
    var window = dinner && free.find(function(candidate){ return candidate.before.id === dinner.id; });
    if(!window){
      window = free.reduce(function(longest, candidate){
        return !longest || candidate.end - candidate.start > longest.end - longest.start ? candidate : longest;
      }, null);
    }
    return '<div class="lkDayMetric lkFactFree"><i class="lkBadge">Volno</i><b>' + durationLabel(window.end - window.start) +
      '</b><small>' + minutesToTime(window.start) + '-' + minutesToTime(window.end) + '</small></div>';
  }
  function renderStayOverview(data){
    var main = document.querySelector('main.content');
    if(!main) return;
    var allDates = dates(data);
    var cards = allDates.map(function(day){
      var items = dayItems(data, day);
      var overviewSummary = { isToday: false, current: null };
      var detail = items.map(function(item){ return renderTimelineItem(item, overviewSummary); }).join('');
      return '<details class="lkOverviewDay lkSectionCard"><summary><div class="lkOverviewDayHead"><h2>' + escapeHtml(dateLabel(day)) +
        '</h2><span>' + items.length + ' ' + itemWord(items.length) + '</span></div><div class="lkDaySummary">' +
        overviewProcedureTile(items) + overviewFreeTile(items) + '</div></summary><div class="lkOverviewDetail"><div class="lkTimeline">' +
        detail + '</div></div></details>';
    }).join('');
    main.innerHTML = '<section class="lkOverviewShell lkParentCard" data-lk-stay-overview="1"><div class="lkOverviewHero lkParentHeader"><div class="lkDayK">Přehled pobytu</div><h1>' +
      allDates.length + ' ' + (allDates.length === 1 ? 'den' : allDates.length >= 2 && allDates.length <= 4 ? 'dny' : 'dní') +
      ' v rozpisu</h1></div><div class="lkOverviewDays">' + cards + '</div></section>';
  }
  function enhanceStayView(){
    var main = document.querySelector('main.content');
    if(!main || main.querySelector('[data-lk-stay-view="1"]')) return;
    var topStats = main.querySelector('.topstats');
    var cards = main.querySelectorAll('.card');
    if(!topStats || cards.length < 2) return;
    var infoGrid = cards[0].querySelector('.infoGrid');
    var procedureList = cards[1].querySelector('.list');
    if(!infoGrid || !procedureList) return;
    var metrics = Array.prototype.map.call(topStats.children, function(tile){
      return {
        value: (tile.querySelector('b') || {}).textContent || '—',
        detail: (tile.querySelector('p') || {}).textContent || ''
      };
    });
    var shell = document.createElement('section');
    var header = document.createElement('header');
    var status = document.createElement('section');
    var info = document.createElement('section');
    var procedures = document.createElement('section');
    var settings = null;
    shell.className = 'lkStayHero lkParentCard';
    shell.dataset.lkStayView = '1';
    header.className = 'lkStayHeader';
    header.innerHTML = '<div class="lkDayK">Souhrn pobytu</div><h1>Pobyt</h1>';
    status.className = 'lkStaySection lkSectionCard lkStayStatus';
    status.innerHTML = '<div class="lkSectionHeader"><h2>Stav pobytu</h2></div><div class="lkStayMetrics">' +
      '<section class="lkStayMetric lkTileCard lkStayMetricProcedure"><div class="lkTileHeader"><i class="lkBadge">Procedury</i></div><b>' +
      escapeHtml(metrics[0] && metrics[0].value) + '</b><p>' + escapeHtml(metrics[0] && metrics[0].detail) + '</p></section>' +
      '<section class="lkStayMetric lkTileCard"><div class="lkTileHeader"><i class="lkBadge">Dny</i></div><b>' +
      escapeHtml(metrics[1] && metrics[1].value) + '</b><p>' + escapeHtml(metrics[1] && metrics[1].detail) + '</p></section></div>';
    info.className = 'lkStaySection lkSectionCard lkStayInfoSection';
    info.innerHTML = '<div class="lkSectionHeader"><h2>Informace o pobytu</h2></div>';
    procedures.className = 'lkStaySection lkSectionCard lkStayProcedureSection';
    procedures.innerHTML = '<div class="lkSectionHeader"><h2>Souhrn procedur</h2><i class="lkBadge">Procedury</i></div>';
    info.appendChild(infoGrid);
    if(window.LazenskySchedule && window.LazenskySchedule.renderNotificationSettings){
      var settingsHolder = document.createElement('div');
      settingsHolder.innerHTML = window.LazenskySchedule.renderNotificationSettings();
      settings = settingsHolder.firstElementChild;
      if(settings){
        window.LazenskySchedule.bindNotificationSettings(settings);
      }
    }
    procedureList.classList.add('lkProcedureList');
    procedures.appendChild(procedureList);
    main.innerHTML = '';
    main.appendChild(shell);
    shell.appendChild(header);
    shell.appendChild(status);
    shell.appendChild(info);
    if(settings) shell.appendChild(settings);
    shell.appendChild(procedures);
    main.classList.add('lkStayView');
  }
  function enhanceImportView(){
    var main = document.querySelector('main.content');
    if(!main || main.querySelector('[data-lk-import-view="1"]')) return;
    var exportHero = main.querySelector('.importHero');
    var advanced = main.querySelector('.importAdvanced');
    var status = main.querySelector('.importStatus');
    var meals = main.querySelector('#expMeals');
    var procedures = main.querySelector('#expProcs');
    var advancedDetails = advanced && advanced.querySelector('details');
    if(!exportHero || !advanced || !status || !advancedDetails || !meals || !procedures) return;
    var fallback = document.createElement('details');
    fallback.className = 'lkIcsFallback';
    fallback.dataset.lkIcsFallback = '1';
    fallback.innerHTML = '<summary>Kalendářové soubory</summary><p>Záložní export pro ruční práci s kalendářem.</p>';
    fallback.appendChild(meals);
    fallback.appendChild(procedures);
    var shell = document.createElement('section');
    var header = document.createElement('header');
    var technical = document.createElement('section');
    shell.className = 'lkImportHero lkParentCard';
    shell.dataset.lkImportView = '1';
    header.className = 'lkImportHeader';
    header.innerHTML = '<div class="lkDayK">Import / rozpis</div><h1>Rozpis pobytu</h1>';
    status.className = 'lkImportSection lkSectionCard lkImportStatusSection';
    technical.className = 'lkImportSection lkSectionCard lkImportTechnicalSection';
    technical.innerHTML = '<div class="lkSectionHeader"><h2>Technický import</h2></div>';
    advancedDetails.className = 'lkImportControl';
    fallback.classList.add('lkImportControl');
    technical.appendChild(advancedDetails);
    technical.appendChild(fallback);
    main.innerHTML = '';
    main.appendChild(shell);
    shell.appendChild(header);
    shell.appendChild(status);
    shell.appendChild(technical);
    main.classList.add('lkImportView');
  }
  function renderDayIdentity(day, today){
    var label = '';
    if(day === today) label = 'Dnes';
    else if(day === addDaysIso(today, 1)) label = 'Zítra';
    return '<div class="lkDayIdentity lkSectionHeader"><span class="lkDayDate">' + escapeHtml(dateLabel(day)) +
      '</span>' + (label ? '<i class="lkBadge">' + label + '</i>' : '') + '</div>';
  }
  function refreshLiveBlock(data){
    if(selectedDay !== todayIso()) return;
    var live = liveState(data);
    var card = document.querySelector('[data-lk-live-state]');
    if(!live || !card || card.getAttribute('data-lk-live-state') !== live.state) return;
    if(live.state !== 'UPCOMING') return;
    var node = card.querySelector('[data-lk-live-countdown="1"]');
    if(!node) return;
    var text = 'Vyrazit za ' + liveCountdown(live.minutesUntilLeave);
    if(node.textContent !== text) node.textContent = text;
  }

  function renderOverview(data, day){
    var items = dayItems(data, day);
    var summary = buildSummary(items, day);
    var today = todayIso();
    var main = document.querySelector('main.content');
    if(!main) return;
    var timelineHtml = items.length
      ? renderProgramTimeline(items, summary)
      : '<div class="lkEmpty">Tenhle den je bez procedur i jídel.</div>';

    main.innerHTML =
      '<div class="lkDayView" data-lk-day-swipe="1"><section class="lkDayHero lkParentCard" data-lk-overview="1"><header class="lkParentHeader"><div class="lkDayK">' +
        (day === today ? 'Dnešní program' : 'Den pobytu') + '</div></header><section class="lkDayOverview lkSectionCard">' + renderDayIdentity(day, today) +
      '<div class="lkDaySummary">' + renderProcedureFact(summary) + renderFreeFact(summary) + '</div>' +
        renderLiveCard(data, day) + renderNextProcedureCard(summary, data, day) +
      '</section><section class="lkProgram lkSectionCard"><div class="lkProgramTitle"><h2>Program dne</h2><span>' + items.length + ' ' +
        itemWord(items.length) + '</span></div>' + timelineHtml + '</section></section></div>';
  }

  function sync(){
    if(busy) return;
    var tab = activeTab();
    renameNavigation();
    var data = readData();
    if(tab === 'week'){
      if(!data || !data.items.length) return;
      var overviewMain = document.querySelector('main.content');
      var overviewState = scheduleStateKey(data, 'overview');
      if(overviewMain && overviewMain.querySelector('[data-lk-stay-overview="1"]') && overviewState === lastStaticState) return;
      busy = true;
      renderStayOverview(data);
      lastStaticState = overviewState;
      busy = false;
      return;
    }
    if(tab === 'stay'){
      enhanceStayView();
      return;
    }
    if(tab === 'import'){
      enhanceImportView();
      return;
    }
    if(tab !== 'today' && tab !== 'tomorrow') return;
    if(!data || !data.items.length) return;
    var allDates = dates(data);
    if(tab !== lastTab || !selectedDay || allDates.indexOf(selectedDay) < 0){
      selectedDay = defaultDay(allDates, tab);
      lastTab = tab;
    }
    var main = document.querySelector('main.content');
    var nextUiState = overviewStateKey(data, selectedDay, tab);
    if(main && main.querySelector('[data-lk-overview="1"]') && nextUiState === lastUiState){
      refreshLiveBlock(data);
      return;
    }
    busy = true;
    renderOverview(data, selectedDay);
    lastUiState = nextUiState;
    busy = false;
  }

  document.addEventListener('touchstart', function(event){
    if(!event.target.closest('[data-lk-day-swipe]') || event.touches.length !== 1) return;
    swipeStart = { x: event.touches[0].clientX, y: event.touches[0].clientY };
  }, { passive: true });
  document.addEventListener('touchend', function(event){
    if(!swipeStart || !event.target.closest('[data-lk-day-swipe]') || !event.changedTouches.length) return;
    var x = event.changedTouches[0].clientX - swipeStart.x;
    var y = event.changedTouches[0].clientY - swipeStart.y;
    swipeStart = null;
    if(Math.abs(x) < 56 || Math.abs(x) <= Math.abs(y)) return;
    var data = readData();
    if(!data || !selectedDay) return;
    var allDates = dates(data);
    var index = allDates.indexOf(selectedDay);
    var nextIndex = Math.max(0, Math.min(allDates.length - 1, index + (x < 0 ? 1 : -1)));
    if(nextIndex === index) return;
    selectedDay = allDates[nextIndex];
    busy = true;
    renderOverview(data, selectedDay);
    lastUiState = overviewStateKey(data, selectedDay, activeTab());
    busy = false;
  }, { passive: true });

  new MutationObserver(function(){ window.requestAnimationFrame(sync); })
    .observe(document.body, { childList: true, subtree: true });
  window.addEventListener('storage', sync);
  window.addEventListener('lazensky-schedule-change', function(){
    lastUiState = '';
    lastStaticState = '';
    sync();
  });
  document.addEventListener('visibilitychange', function(){
    if(!document.hidden) sync();
  });
  window.addEventListener('focus', sync);
  window.addEventListener('load', sync);
  window.setInterval(sync, 30000);
  sync();
})();
