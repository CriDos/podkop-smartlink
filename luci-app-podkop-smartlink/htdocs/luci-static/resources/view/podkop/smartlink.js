"use strict";
"require view";
"require form";
"require fs";
"require ui";

/* ============================================================ */
/* i18n                                                         */
/* ============================================================ */

var I18N = {
  ru: {
    tabSettings: "Настройки",
    general: "Основные",
    tabSources: "Подписки",
    updateInterval: "Обновление списка",
    updateIntervalDesc: "Как часто обновлять список серверов из подписки.",
    xhttp: "Расширенные транспорты",
    xhttpDesc: "Включите, если установлен расширенный sing-box.",
    usePriority: "Приоритет источников",
    usePriorityDesc: "Учитывать порядок подписок при выборе сервера. Источник #1 имеет преимущество.",
    selectedVpn: "Мониторинг активного сервера",
    checkInterval: "Проверка каждые",
    checkIntervalDesc: "Раз в N секунд пингуется активный сервер.",
    maxPing: "Лимит пинга",
    maxPingDesc: "Пинг выше этого значения считается ошибкой.",
    failCount: "Переключение после",
    failCountDesc: "После N ошибок подряд пингуются все серверы и выбирается лучший.",
    allVpn: "Мониторинг всех серверов",
    about: "О системе",
    version: "Версия",
    uptime: "Аптайм",
    pingAllInterval: "Проверка каждые",
    pingAllIntervalDesc: "Раз в N секунд пингуются все сервера.",
    pingTimeout: "Таймаут пинга",
    pingTimeoutDesc: "Сколько миллисекунд ждать ответа от сервера.",
    testUrl: "URL теста задержки",
    testUrlDesc: "Адрес для проверки пинга через туннель.",
    noSources: "Нет источников. Добавьте подписку или прямую ссылку ниже.",
    refreshSubs: "Обновить подписки",
    save: "Применить",
    saved: "Сохранено",
    saving: "Сохраняем…",
    refreshing: "Обновляем…",
    error: "Ошибка",
    addSource: "Добавить",
    urlPlaceholder: "https://… или vless://…",
    invalidUrl: "Неверный формат. Используйте ссылку подписки (https://) или прокси (vless://, ss://, trojan://, hy2://, hysteria2://, socks://)",
    duplicateUrl: "Этот источник уже есть в списке",
    colName: "Название",
    colPing: "Пинг",
    colAvail: "Дост.",
    colStab: "Стаб.",
    select: "Выбрать",
    active: "Активен",
    noServers: "Нет серверов",
    pinging: "Пингуем…",
    pingSourceHint: "Пинг источника",
    resetStatsHint: "Сбросить статистику",
    confirmDelete: "Удалить источник",
    ms: "мс",
    statsReset: "Статистика сброшена",
    proxySelected: "Выбран сервер",
    copied: "Скопировано",
    refreshDone: "Подписки обновлены",
    refreshFailed: "Не удалось обновить подписки",
    totalServers: "Всего серверов",
    aliveServers: "Живых",
    currentVpn: "Текущий VPN",
    notSelected: "не выбран",
    lastUpdated: "Обновлено",
    autoRefresh: "авто",
    never: "никогда",
    aboutTitle: "Podkop SmartLink",
    aboutDesc: "Companion для Podkop — импорт VPN-подписок и sticky health-checked выбор сервера для selector-группы sing-box.",
    aboutProject: "Проект",
    aboutSystem: "Система",
    aboutLinks: "Ссылки",
    aboutGitHub: "GitHub",
    aboutPodkop: "Podkop",
    aboutIssues: "Сообщить о проблеме",
    aboutMemory: "Память",
    aboutLoad: "Загрузка",
    aboutArch: "Архитектура",
    aboutKernel: "Ядро",
    aboutFree: "Свободно",
    aboutUsed: "Занято",
  },
  en: {
    tabSettings: "Settings",
    general: "General",
    tabSources: "Subscriptions",
    updateInterval: "List update",
    updateIntervalDesc: "How often to refresh the server list from subscriptions.",
    xhttp: "Extended transports",
    xhttpDesc: "Enable if extended sing-box is installed.",
    usePriority: "Source priority",
    usePriorityDesc: "Consider subscription order when selecting server. Source #1 has advantage.",
    selectedVpn: "Active server monitoring",
    checkInterval: "Check every",
    checkIntervalDesc: "Ping the active server every N seconds.",
    maxPing: "Ping limit",
    maxPingDesc: "Ping above this value counts as an error.",
    failCount: "Switch after",
    failCountDesc: "After N consecutive errors, all servers are pinged and the best is selected.",
    allVpn: "All servers monitoring",
    about: "About",
    version: "Version",
    uptime: "Uptime",
    pingAllInterval: "Check every",
    pingAllIntervalDesc: "All servers are pinged every N seconds.",
    pingTimeout: "Ping timeout",
    pingTimeoutDesc: "How many milliseconds to wait for a server response.",
    testUrl: "Latency test URL",
    testUrlDesc: "URL for ping check through the tunnel.",
    noSources: "No sources. Add a subscription or direct link below.",
    refreshSubs: "Refresh subscriptions",
    save: "Apply",
    saved: "Saved",
    saving: "Saving…",
    refreshing: "Refreshing…",
    error: "Error",
    addSource: "Add",
    urlPlaceholder: "https://… or vless://…",
    invalidUrl: "Invalid format. Use a subscription URL (https://) or proxy link (vless://, ss://, trojan://, hy2://, hysteria2://, socks://)",
    duplicateUrl: "This source is already in the list",
    colName: "Name",
    colPing: "Ping",
    colAvail: "Avail.",
    colStab: "Stab.",
    select: "Select",
    active: "Active",
    noServers: "No servers",
    pinging: "Pinging…",
    pingSourceHint: "Ping source",
    resetStatsHint: "Reset statistics",
    confirmDelete: "Delete source",
    ms: "ms",
    statsReset: "Statistics reset",
    proxySelected: "Server selected",
    copied: "Copied",
    refreshDone: "Subscriptions refreshed",
    refreshFailed: "Failed to refresh subscriptions",
    totalServers: "Total servers",
    aliveServers: "Alive",
    currentVpn: "Current VPN",
    notSelected: "not selected",
    lastUpdated: "Updated",
    autoRefresh: "auto",
    never: "never",
    aboutTitle: "Podkop SmartLink",
    aboutDesc: "Companion for Podkop — import VPN subscriptions and sticky health-checked server selection for sing-box selector groups.",
    aboutProject: "Project",
    aboutSystem: "System",
    aboutLinks: "Links",
    aboutGitHub: "GitHub",
    aboutPodkop: "Podkop",
    aboutIssues: "Report an issue",
    aboutMemory: "Memory",
    aboutLoad: "Load",
    aboutArch: "Architecture",
    aboutKernel: "Kernel",
    aboutFree: "Free",
    aboutUsed: "Used",
  },
};

function detectLang() {
  var h = document.documentElement.lang || "";
  if (h.indexOf("ru") === 0) return "ru";
  if (h.indexOf("en") === 0) return "en";
  var n = navigator.language || "";
  if (n.indexOf("ru") === 0) return "ru";
  return "en";
}

var LANG = detectLang();
function t(key) {
  return (I18N[LANG] && I18N[LANG][key]) || I18N.ru[key] || key;
}

/* ============================================================ */
/* API layer                                                    */
/* ============================================================ */

var BIN = "/usr/bin/podkop-smartlink";

function execCmd(args, stdin) {
  return fs.exec(BIN, args, stdin).then(function (res) {
    var out = (res && res.stdout) || "";
    try { return JSON.parse(out); } catch (e) { return { error: "parse_error", raw: out }; }
  });
}

var api = {
  status: function () { return execCmd(["get_status"]); },
  sources: function () { return execCmd(["get_sources"]); },
  pingAll: function () { return execCmd(["ping_all"]); },
  pingSource: function (idx) { return execCmd(["ping_source", String(idx)]); },
  resetSource: function (idx) { return execCmd(["reset_source_stats", String(idx)]); },
  resetAll: function () { return execCmd(["reset_stats"]); },
  selectProxy: function (tag) { return execCmd(["select_proxy", tag]); },
  refresh: function () { return execCmd(["refresh_now"]); },
  saveSources: function (list) {
    var urls = list.map(function (s) { return { url: s.url }; });
    return execCmd(["save_sources", JSON.stringify(urls)]);
  },
  applyChanges: function (changedHashes) {
    return execCmd(["apply_changes", changedHashes.join(",")]);
  },
  saveConfig: function () { return execCmd(["save_config"]); },
  getInfo: function () { return execCmd(["get_info"]); },
};

/* ============================================================ */
/* Helpers                                                      */
/* ============================================================ */

function el(tag, attrs, children) {
  var node = document.createElement(tag);
  if (attrs) {
    Object.keys(attrs).forEach(function (k) {
      if (k === "class") node.className = attrs[k];
      else if (k === "style") node.setAttribute("style", attrs[k]);
      else if (k.startsWith("on") && typeof attrs[k] === "function")
        node.addEventListener(k.slice(2), attrs[k]);
      else node.setAttribute(k, attrs[k]);
    });
  }
  (children || []).forEach(function (c) {
    if (c == null) return;
    node.appendChild(typeof c === "string" ? document.createTextNode(c) : c);
  });
  return node;
}

function setBusy(busy) {
  state.busy = busy;
  var btns = document.querySelectorAll(".sl-bottom-bar button, .sl-icon-btn, .sl-select-btn");
  btns.forEach(function (b) { b.disabled = busy; });
}

function fmtPing(p) {
  if (!p) return "0 " + t("ms");
  return p + " " + t("ms");
}

function fmtPct(s) {
  if (!s) return "—";
  return Math.round(s * 100) + "%";
}

function metricColor(s) {
  if (!s) return "";
  var pct = Math.round(s * 100);
  return pct >= 90 ? "sl-ok" : pct >= 70 ? "sl-warn" : "sl-bad";
}

function pingColor(p) {
  if (!p) return "sl-bad";
  if (p <= 80) return "sl-ping-fast";
  if (p <= 150) return "sl-ping-good";
  if (p <= 250) return "sl-ping-ok";
  if (p <= 400) return "sl-ping-slow";
  return "sl-ping-bad";
}

function timeAgo(ts) {
  if (!ts || ts === 0) return "";
  var d = new Date(ts * 1000);
  var dd = String(d.getDate()).padStart(2, "0");
  var mm = String(d.getMonth() + 1).padStart(2, "0");
  var hh = String(d.getHours()).padStart(2, "0");
  var mi = String(d.getMinutes()).padStart(2, "0");
  return dd + "." + mm + " " + hh + ":" + mi;
}

/* ============================================================ */
/* State                                                        */
/* ============================================================ */

var state = {
  sources: [],
  proxies: [],
  current: null,
  lastUpdate: 0,
  expanded: {},
  sortKey: {},
  sortDir: {},
  activeTab: localStorage.getItem("sl_active_tab") || "settings",
  pinging: {},   // source idx -> true while pinging
  dirty: false,  // local unsaved changes to sources
};

var sourcesContainer = null;

function loadStatus() {
  return api.status().then(function (st) {
    if (!st || st.error) return;
    state.proxies = st.proxies || [];
    state.current = st.current || null;
    state.lastUpdate = st.last_update || 0;
    if (state.activeTab === "sources" && sourcesContainer && !state.dirty) renderSources();
  });
}

function loadAll() {
  return Promise.all([api.sources(), api.status()]).then(function (r) {
    var srcs = r[0], st = r[1];
    if (!state.dirty) {
      state.sources = (srcs && srcs.sources) || [];
    }
    state.proxies = (st && st.proxies) || [];
    state.current = (st && st.current) || null;
    state.lastUpdate = (st && st.last_update) || 0;
    if (sourcesContainer) renderSources();
  });
}

/* ============================================================ */
/* Toast                                                        */
/* ============================================================ */

function toast(msg, type) {
  var t2 = el("div", { class: "sl-toast" + (type ? " sl-toast-" + type : "") }, [msg]);
  document.body.appendChild(t2);
  setTimeout(function () { t2.classList.add("sl-toast-show"); }, 10);
  setTimeout(function () {
    t2.classList.remove("sl-toast-show");
    setTimeout(function () { if (t2.parentNode) t2.parentNode.removeChild(t2); }, 300);
  }, 2500);
}

/* ============================================================ */
/* VPN table                                                    */
/* ============================================================ */

var TABLE_COLS = [
  { key: "title", label: "colName" },
  { key: "ping", label: "colPing", numeric: true, defaultDir: "asc" },
  { key: "availability", label: "colAvail", numeric: true, defaultDir: "desc" },
  { key: "stability", label: "colStab", numeric: true, defaultDir: "desc" },
  { key: "action", label: "", action: true },
];

function sortProxies(proxies, srcIdx) {
  var sk = state.sortKey[srcIdx] || "ping";
  var sd = state.sortDir[srcIdx] || "asc";
  var sorted = proxies.slice();
  sorted.sort(function (a, b) {
    var va, vb;
    if (sk === "ping") { va = a.ping || 99999; vb = b.ping || 99999; }
    else if (sk === "availability") { va = a.availability || 0; vb = b.availability || 0; }
    else if (sk === "stability") { va = a.stability || 0; vb = b.stability || 0; }
    else { va = (a[sk] || "").toLowerCase(); vb = (b[sk] || "").toLowerCase(); }
    if (typeof va === "number") return sd === "asc" ? va - vb : vb - va;
    if (va < vb) return sd === "asc" ? -1 : 1;
    if (va > vb) return sd === "asc" ? 1 : -1;
    return 0;
  });
  return sorted;
}

function renderVpnTable(container, proxies, srcIdx) {
  var sorted = sortProxies(proxies, srcIdx);
  var sk = state.sortKey[srcIdx] || "ping";
  var sd = state.sortDir[srcIdx] || "asc";
  container.innerHTML = "";

  if (!sorted.length) {
    container.appendChild(el("div", { class: "sl-empty" }, [t("noServers")]));
    return;
  }

  var table = el("table", { class: "sl-vpn-table" });
  var thead = el("thead", {});
  var hr = el("tr", {});

  TABLE_COLS.forEach(function (col) {
    if (col.action) { hr.appendChild(el("th", { style: "width:90px;" })); return; }
    var width = col.numeric ? (col.key === "ping" ? "70px" : "60px") : "auto";
    var th = el("th", { class: "sl-th" + (col.key === sk ? " sl-th-active" : ""), style: "width:" + width + ";" });
    th.appendChild(document.createTextNode(t(col.label)));
    if (col.key === sk) {
      th.appendChild(el("span", { class: "sl-sort-arrow" }, [sd === "asc" ? "▲" : "▼"]));
    }
    th.addEventListener("click", function () {
      if (state.sortKey[srcIdx] === col.key)
        state.sortDir[srcIdx] = state.sortDir[srcIdx] === "asc" ? "desc" : "asc";
      else { state.sortKey[srcIdx] = col.key; state.sortDir[srcIdx] = col.defaultDir || "asc"; }
      renderVpnTable(container, proxies, srcIdx);
    });
    hr.appendChild(th);
  });
  thead.appendChild(hr);
  table.appendChild(thead);

  var tbody = el("tbody", {});
  sorted.forEach(function (p) {
    var tr = el("tr", { class: p.selected ? "sl-row-selected" : "" });

    var nameTd = el("td", { class: "sl-td-name" }, [p.title || "—"]);
    if (p.selected) nameTd.classList.add("sl-bold");
    tr.appendChild(nameTd);

    // Ping: "—" if never pinged (no checks), "0" red if dead, else value
    var neverPing = !p.checks || p.checks === 0;
    var pingTd = el("td", { class: "sl-td-ping sl-bold " + (neverPing ? "" : (pingColor(p.ping) || "sl-bad")) });
    pingTd.textContent = neverPing ? "—" : fmtPing(p.ping);
    tr.appendChild(pingTd);

    // Stats: always show if any history exists (checks > 0)
    var hasStats = p.checks && p.checks > 0;
    var avTd = el("td", { class: "sl-td-metric " + (hasStats ? (metricColor(p.availability) || "") : "") });
    avTd.textContent = hasStats ? fmtPct(p.availability) : "—";
    tr.appendChild(avTd);

    var stTd = el("td", { class: "sl-td-metric " + (hasStats ? (metricColor(p.stability) || "") : "") });
    stTd.textContent = hasStats ? fmtPct(p.stability) : "—";
    tr.appendChild(stTd);

    var actTd = el("td", { class: "sl-td-action" });
    var btn = el("button", { class: "cbi-button cbi-button-apply sl-select-btn" });
  if (state.busy) btn.disabled = true;
    if (!p.tag) {
      btn.disabled = true; btn.textContent = "—";
    } else if (p.selected) {
      btn.disabled = true; btn.textContent = t("active");
      btn.classList.add("sl-btn-active");
    } else {
      btn.textContent = t("select");
      btn.addEventListener("click", function () {
        btn.disabled = true; btn.textContent = "…";
        api.selectProxy(p.tag).then(function (res) {
          if (!res || res.error) {
            btn.disabled = false; btn.textContent = t("select");
            toast(t("error"), "err");
            return;
          }
          toast(t("proxySelected"), "ok");
          // Update global state
          state.proxies.forEach(function (pp) { pp.selected = (pp.tag === p.tag); });
          if (res.current) state.current = res.current;
          // Update summary bar (current VPN title)
          var sumVal = document.querySelector(".sl-summary .sl-summary-value");
          if (sumVal) {
            sumVal.textContent = state.current ? state.current.title : t("notSelected");
            sumVal.className = "sl-summary-value" + (state.current ? " sl-ok" : "");
          }
          // Update source row highlights (add/remove sl-source-active)
          state.sources.forEach(function (src, si) {
            var row = document.querySelector(".sl-source-wrapper[data-idx='" + si + "'] .sl-source-row");
            if (!row) return;
            var hasSel = state.proxies.some(function (pp) { return pp.source === si && pp.selected; });
            row.classList.toggle("sl-source-active", hasSel);
          });
          // Re-render all expanded VPN tables (old active + new active)
          Object.keys(state.expanded).forEach(function (idx) {
            var i = parseInt(idx, 10);
            var div = document.querySelector("[data-vpn='" + i + "']");
            if (div) {
              var srcProxies = state.proxies.filter(function (pp) { return pp.source === i; });
              renderVpnTable(div, srcProxies, i);
            }
          });
        }, function () {
          btn.disabled = false; btn.textContent = t("select");
          toast(t("error"), "err");
        });
      });
    }
    actTd.appendChild(btn);
    tr.appendChild(actTd);
    tbody.appendChild(tr);
  });
  table.appendChild(tbody);
  container.appendChild(table);
}

/* ============================================================ */
/* Sources tab                                                  */
/* ============================================================ */

function renderSources() {
  if (!sourcesContainer) return;
  sourcesContainer.innerHTML = "";

  // Summary bar
  var aliveCount = state.proxies.filter(function (p) { return p.ping > 0; }).length;
  var totalCount = state.proxies.length;
  var curTitle = state.current ? state.current.title : t("notSelected");
  var summary = el("div", { class: "sl-summary" }, [
    el("span", { class: "sl-summary-item" }, [
      el("span", { class: "sl-summary-label" }, [t("currentVpn") + ":"]),
      el("span", { class: "sl-summary-value" + (state.current ? " sl-ok" : "") }, [curTitle]),
    ]),
    el("span", { class: "sl-summary-item" }, [
      el("span", { class: "sl-summary-label" }, [t("totalServers") + ":"]),
      el("span", { class: "sl-summary-value" }, [
        el("span", { class: aliveCount > 0 ? "sl-ok" : "sl-bad" }, [String(aliveCount)]),
        "/" + String(totalCount),
      ]),
    ]),
  ]);
  sourcesContainer.appendChild(summary);

  // Empty state
  if (!state.sources.length) {
    sourcesContainer.appendChild(el("div", { class: "sl-alert" }, [t("noSources")]));
  }

  // Source rows
  var list = el("div", { class: "sl-source-list" });
  state.sources.forEach(function (src, i) {
    list.appendChild(renderSourceRow(src, i));
  });
  sourcesContainer.appendChild(list);
  attachDragDrop(list);

  // Add new source
  sourcesContainer.appendChild(renderAddRow());

  // Bottom buttons: refresh + save
  var bottomBar = el("div", { class: "sl-bottom-bar" });

  // Shared: wait for background refresh to finish, then reload UI
  function waitForRefresh(btn, btnLabel, onSuccess) {
    var attempts = 0;
    function poll() {
      if (attempts++ > 60) {
        btn.disabled = false;
        btn.textContent = btnLabel;
        toast(t("refreshFailed"), "err");
        loadAll();
        return;
      }
      api.status().then(function (st) {
        if (st && !st.error && !st.refreshing) {
          btn.disabled = false;
          btn.textContent = btnLabel;
          if (onSuccess) onSuccess();
          else { toast(t("refreshDone"), "ok"); }
          loadAll();
        } else if (st && st.error) {
          setTimeout(poll, 1500);
        } else {
          setTimeout(poll, 1500);
        }
      }, function () { setTimeout(poll, 1500); });
    }
    setTimeout(poll, 2000);
  }

  var refreshBtn = el("button", { class: "cbi-button" }, [t("refreshSubs")]);
  refreshBtn.addEventListener("click", function () {
    if (state.busy) return;
    setBusy(true);
    refreshBtn.disabled = true; refreshBtn.textContent = t("refreshing");
    api.refresh().then(function () {
      waitForRefresh(refreshBtn, t("refreshSubs"), function () {
        toast(t("refreshDone"), "ok");
        setBusy(false);
      });
    }, function () {
      refreshBtn.disabled = false; refreshBtn.textContent = t("refreshSubs");
      toast(t("error"), "err");
      setBusy(false);
    });
  });
  bottomBar.appendChild(refreshBtn);

  var saveBtn = el("button", { class: "cbi-button cbi-button-save" }, [t("save")]);
  saveBtn.addEventListener("click", function () {
    if (state.busy) return;
    setBusy(true);
    saveBtn.disabled = true; saveBtn.textContent = t("saving");
    api.saveSources(state.sources).then(function (res) {
      if (!res || res.error) {
        saveBtn.disabled = false; saveBtn.textContent = t("save");
        toast(t("error"), "err");
        setBusy(false);
        return;
      }
      state.dirty = false;
      if (res.changed === 0) {
        saveBtn.disabled = false; saveBtn.textContent = t("save");
        toast(t("saved"), "ok");
        setBusy(false);
        loadAll();
        return;
      }
      var changedHashes = res.changed_hashes || [];
      saveBtn.textContent = t("refreshing");
      api.applyChanges(changedHashes).then(function () {
        waitForRefresh(saveBtn, t("save"), function () {
          toast(t("saved"), "ok");
          setBusy(false);
          loadAll();
        });
      }, function () {
        saveBtn.disabled = false; saveBtn.textContent = t("save");
        toast(t("error"), "err");
        setBusy(false);
      });
    }, function () {
      saveBtn.disabled = false; saveBtn.textContent = t("save");
      toast(t("error"), "err");
      setBusy(false);
    });
  });
  bottomBar.appendChild(saveBtn);
  sourcesContainer.appendChild(bottomBar);
}

function renderSourceRow(src, i) {
  var srcProxies = state.proxies.filter(function (p) { return p.source === i; });
  var aliveCount = srcProxies.filter(function (p) { return p.ping > 0; }).length;
  var isPinging = !!state.pinging[i];
  var hasSelected = srcProxies.some(function (p) { return p.selected; });
  var urlDisplay = src.url.length > 70 ? src.url.substring(0, 67) + "…" : src.url;

  var row = el("div", {
    class: "sl-source-row" + (isPinging ? " sl-source-pinging" : "") + (hasSelected ? " sl-source-active" : ""),
  });

  // Drag handle (only this triggers drag, not the whole row)
  var dragHandle = el("span", { class: "sl-drag-handle", draggable: "true" }, ["☰"]);
  row.appendChild(dragHandle);

  // Expand/collapse
  var expandBtn = el("span", { class: "sl-expand-btn" },
    [state.expanded[i] ? "▾" : "▸"]);
  row.appendChild(expandBtn);

  // URL
  var urlEl = el("span", { class: "sl-source-url", title: src.url }, [urlDisplay]);
  urlEl.addEventListener("click", function () {
    var tmp = el("input", {});
    tmp.value = src.url;
    document.body.appendChild(tmp);
    tmp.select();
    document.execCommand("copy");
    document.body.removeChild(tmp);
    toast(t("copied"), "ok");
  });
  row.appendChild(urlEl);

  // Server count: alive/total (only after proxies are loaded)
  if (srcProxies.length) {
    var aliveSpan = el("span", { class: aliveCount > 0 ? "sl-ok" : "sl-bad" }, [String(aliveCount)]);
    var countSpan = el("span", { class: "sl-server-count" }, [
      aliveSpan, "/", el("span", {}, [String(srcProxies.length)]),
    ]);
    row.appendChild(countSpan);
  }

  // Last update time (all source types)
  var lastUp = src.last_update || 0;
  var timeStr = timeAgo(lastUp);
  if (timeStr) {
    row.appendChild(el("span", { class: "sl-source-time" }, [timeStr]));
  }

  // Priority
  row.appendChild(el("span", { class: "sl-priority" }, ["#" + (i + 1)]));

  // Ping button
  var pingIcon = isPinging
    ? el("span", { class: "sl-spin-icon" }, ["⟳"])
    : document.createTextNode("⚡");
  var pingBtn = el("button", {
    class: "cbi-button sl-icon-btn",
    title: t("pingSourceHint"),
  }, [pingIcon]);
  if (isPinging) pingBtn.disabled = true;
  pingBtn.addEventListener("click", function () {
    if (state.busy || state.pinging[i]) return;
    state.pinging[i] = true;
    renderSources();
    api.pingSource(i).then(function () {
      delete state.pinging[i];
      loadStatus();
    }).catch(function () {
      delete state.pinging[i];
      renderSources();
    });
  });
  row.appendChild(pingBtn);

  // Reset button
  var resetBtn = el("button", {
    class: "cbi-button sl-icon-btn",
    title: t("resetStatsHint"),
  }, ["⊘"]);
  resetBtn.addEventListener("click", function () {
    if (state.busy) return;
    // Optimistic: clear stats in local state immediately
    srcProxies.forEach(function (p) {
      p.availability = 0; p.stability = 0; p.checks = 0;
    });
    if (state.expanded[i]) {
      var vpnDiv = document.querySelector("[data-vpn='" + i + "']");
      if (vpnDiv) renderVpnTable(vpnDiv, srcProxies, i);
    }
    renderSources();
    // Fire backend (instant, no status rebuild)
    api.resetSource(i).then(function () {
      toast(t("statsReset"), "ok");
      loadStatus();
    });
  });
  row.appendChild(resetBtn);

  // Delete
  var delBtn = el("button", { class: "cbi-button sl-icon-btn sl-btn-danger", title: t("confirmDelete") }, ["×"]);
  delBtn.addEventListener("click", function () {
    if (confirm(t("confirmDelete"))) {
      state.sources.splice(i, 1);
      state.proxies = state.proxies.filter(function (p) { return p.source !== i; });
      state.proxies.forEach(function (p) { if (p.source > i) p.source--; });
      state.dirty = true;
      delete state.expanded[i];
      var newExpanded = {};
      Object.keys(state.expanded).forEach(function (k) {
        var ki = parseInt(k, 10);
        if (ki < i) newExpanded[ki] = state.expanded[k];
        else if (ki > i) newExpanded[ki - 1] = state.expanded[k];
      });
      state.expanded = newExpanded;
      ["sortKey", "sortDir", "pinging"].forEach(function (key) {
        var newObj = {};
        Object.keys(state[key]).forEach(function (k) {
          var ki = parseInt(k, 10);
          if (ki < i) newObj[ki] = state[key][k];
          else if (ki > i) newObj[ki - 1] = state[key][k];
        });
        state[key] = newObj;
      });
      renderSources();
    }
  });
  row.appendChild(delBtn);

  // Expandable VPN table
  var vpnDiv = el("div", { class: "sl-vpn-container" + (state.expanded[i] ? "" : " sl-hidden") });
  vpnDiv.setAttribute("data-vpn", String(i));

  expandBtn.addEventListener("click", function () {
    if (state.expanded[i]) {
      delete state.expanded[i];
      vpnDiv.classList.add("sl-hidden");
      expandBtn.textContent = "▸";
    } else {
      state.expanded[i] = true;
      vpnDiv.classList.remove("sl-hidden");
      expandBtn.textContent = "▾";
      renderVpnTable(vpnDiv, srcProxies, i);
    }
  });

  if (state.expanded[i]) renderVpnTable(vpnDiv, srcProxies, i);

  var wrapper = el("div", { class: "sl-source-wrapper", "data-idx": String(i) }, [row, vpnDiv]);

  // Drag: only from handle
  dragHandle.addEventListener("dragstart", function (e) {
    e.dataTransfer.setData("text/plain", String(i));
    e.dataTransfer.effectAllowed = "move";
    wrapper.classList.add("sl-dragging");
    // Set a drag image to the wrapper itself
    if (e.dataTransfer.setDragImage) {
      e.dataTransfer.setDragImage(wrapper, 10, 10);
    }
  });
  dragHandle.addEventListener("dragend", function () {
    wrapper.classList.remove("sl-dragging");
    dragState.cleanup();
  });

  return wrapper;
}

/* ---- Drag-and-drop: container-level, stable, no flicker ---- */
var dragState = {
  indicator: null,
  rafId: 0,
  targetIdx: -1,
  before: true,    // insert before target (true) or after (false)

  cleanup: function () {
    if (this.rafId) { cancelAnimationFrame(this.rafId); this.rafId = 0; }
    if (this.indicator) { this.indicator.remove(); this.indicator = null; }
    this.targetIdx = -1;
  },

  ensureIndicator: function () {
    if (!this.indicator) {
      this.indicator = el("div", { class: "sl-drag-indicator" });
    }
    return this.indicator;
  },

  moveIndicator: function (wrapper, before) {
    var ind = this.ensureIndicator();
    if (ind.parentNode) ind.parentNode.removeChild(ind);
    if (before) {
      wrapper.parentNode.insertBefore(ind, wrapper);
    } else {
      var next = wrapper.nextSibling;
      if (next) wrapper.parentNode.insertBefore(ind, next);
      else wrapper.parentNode.appendChild(ind);
    }
  },
};

function attachDragDrop(listEl) {
  var pendingEvent = null;

  listEl.addEventListener("dragover", function (e) {
    e.preventDefault();
    e.dataTransfer.dropEffect = "move";
    pendingEvent = e;
    if (!dragState.rafId) {
      dragState.rafId = requestAnimationFrame(function () {
        dragState.rafId = 0;
        if (!pendingEvent) return;
        var ev = pendingEvent;
        pendingEvent = null;
        var wrapper = ev.target.closest ? ev.target.closest(".sl-source-wrapper") : null;
        if (!wrapper) return;
        var idx = parseInt(wrapper.getAttribute("data-idx"), 10);
        var rect = wrapper.getBoundingClientRect();
        var isTop = (ev.clientY - rect.top) < rect.height / 2;
        dragState.targetIdx = idx;
        dragState.before = isTop;
        dragState.moveIndicator(wrapper, isTop);
      });
    }
  });

  listEl.addEventListener("drop", function (e) {
    e.preventDefault();
    var fromIdx = parseInt(e.dataTransfer.getData("text/plain"), 10);
    dragState.cleanup();
    if (isNaN(fromIdx)) return;

    var wrapper = e.target.closest ? e.target.closest(".sl-source-wrapper") : null;
    if (!wrapper) return;
    var targetIdx = parseInt(wrapper.getAttribute("data-idx"), 10);
    var rect = wrapper.getBoundingClientRect();
    var isTop = (e.clientY - rect.top) < rect.height / 2;

    if (fromIdx === targetIdx) return;
    var item = state.sources.splice(fromIdx, 1)[0];
    var insertAt = targetIdx;
    if (fromIdx < targetIdx) insertAt = targetIdx - 1;
    if (!isTop) insertAt = insertAt + 1;
    state.sources.splice(insertAt, 0, item);
    state.dirty = true;
    renderSources();
  });

  listEl.addEventListener("dragleave", function (e) {
    if (!listEl.contains(e.relatedTarget)) {
      dragState.cleanup();
    }
  });
}

function renderAddRow() {
  var addRow = el("div", { class: "sl-add-row" });

  var urlInput = el("input", {
    type: "text",
    class: "cbi-input-text sl-add-url",
    placeholder: t("urlPlaceholder"),
    style: "height:39px !important; padding:8px 12px !important; box-sizing:border-box !important; font-size:1em !important;",
  });
  addRow.appendChild(urlInput);

  var addBtn = el("button", { class: "cbi-button cbi-button-add" }, [t("addSource")]);
  addBtn.addEventListener("click", function () {
    var v = urlInput.value.trim();
    if (!v) return;
    var vl = v.toLowerCase();
    var ok = vl.startsWith("https://") || vl.startsWith("http://") ||
      vl.startsWith("vless://") || vl.startsWith("ss://") ||
      vl.startsWith("trojan://") || vl.startsWith("hy2://") ||
      vl.startsWith("hysteria2://") || vl.startsWith("socks://") ||
      vl.startsWith("socks4://") || vl.startsWith("socks5://");
    if (!ok) { toast(t("invalidUrl"), "err"); return; }
    if (state.sources.some(function (s) { return s.url === v; })) {
      toast(t("duplicateUrl"), "err"); return;
    }
    state.sources.push({ url: v, last_update: 0 });
    state.dirty = true;
    urlInput.value = "";
    renderSources();
  });
  addRow.appendChild(addBtn);
  return addRow;
}

/* ============================================================ */
/* Tab system                                                   */
/* ============================================================ */

function createTabs(settingsNode, sourcesNode, aboutNode) {
  var wrap = el("div", {});
  var bar = el("div", { class: "sl-tabbar" });

  function mkTab(key, label) {
    var tab = el("div", {
      class: "sl-tab" + (state.activeTab === key ? " sl-tab-active" : ""),
    }, [label]);
    tab.addEventListener("click", function () {
      state.activeTab = key;
      localStorage.setItem("sl_active_tab", key);
      bar.querySelectorAll(".sl-tab").forEach(function (t2) { t2.classList.remove("sl-tab-active"); });
      tab.classList.add("sl-tab-active");
      cSettings.style.display = "none";
      cSources.style.display = "none";
      cAbout.style.display = "none";
      document.querySelectorAll(".cbi-page-actions").forEach(function (a) { a.style.display = "none"; });
      if (key === "settings") {
        cSettings.style.display = "";
        document.querySelectorAll(".cbi-page-actions").forEach(function (a) { a.style.display = ""; });
      } else if (key === "sources") {
        cSources.style.display = "";
      } else if (key === "about") {
        cAbout.style.display = "";
      }
    });
    return tab;
  }

  var tabSettings = mkTab("settings", t("tabSettings"));
  var tabSources = mkTab("sources", t("tabSources"));
  var tabAbout = mkTab("about", t("about"));
  bar.appendChild(tabSettings);
  bar.appendChild(tabSources);
  bar.appendChild(tabAbout);
  wrap.appendChild(bar);

  var cSettings = el("div", { id: "tab-content-settings" }, [settingsNode]);
  var cSources = el("div", { id: "tab-content-sources", class: "sl-sources-tab" }, [sourcesNode]);
  var cAbout = el("div", { id: "tab-content-about", class: "sl-sources-tab" }, [aboutNode]);

  cSettings.style.display = "none";
  cSources.style.display = "none";
  cAbout.style.display = "none";
  if (state.activeTab === "settings") cSettings.style.display = "";
  else if (state.activeTab === "sources") cSources.style.display = "";
  else cAbout.style.display = "";

  wrap.appendChild(cSettings);
  wrap.appendChild(cSources);
  wrap.appendChild(cAbout);

  return wrap;
}

/* ============================================================ */
/* CSS                                                          */
/* ============================================================ */

var CSS = [
  /* Base — unified font size, max-width, padding for all tabs */
  "#tab-content-settings, #tab-content-sources, #tab-content-about { width:100%; margin:0; }",
  ".sl-sources-tab { padding:0; }",

  /* Tabs */
  ".sl-tabbar { display:flex; gap:0; border-bottom:2px solid var(--cbi-color-border,#ccc); margin-bottom:14px; }",
  ".sl-tab { padding:8px 20px; cursor:pointer; opacity:0.6; font-size:0.95em; }",
  ".sl-tab-active { font-weight:bold; border-bottom:6px solid #00a3cc; margin-bottom:-2px; color:#00a3cc; opacity:1; }",

  /* Summary bar */
  ".sl-summary { display:flex; gap:16px; align-items:center; flex-wrap:wrap; padding:12px 16px; margin-bottom:10px;",
  "  border:1px solid var(--cbi-color-border,#ccc); border-radius:8px; font-size:1em; }",
  ".sl-summary-item { display:inline-flex; gap:5px; align-items:baseline; }",
  ".sl-summary-label { opacity:0.6; }",
  ".sl-summary-value { font-weight:bold; }",

  /* Source rows */
  ".sl-source-wrapper { position:relative; }",
  ".sl-source-row { display:flex; align-items:center; gap:8px; padding:7px 14px; margin-bottom:5px;",
  "  border:1px solid var(--cbi-color-border,#ccc); border-radius:8px; font-size:1em; transition:border-color 0.15s, background 0.15s; }",
  ".sl-source-row:hover { border-color:#00a3cc; }",
  ".sl-source-pinging { border-color:#f0ad4e; }",
  ".sl-source-active { border-color:#5cb85c; background:rgba(92,184,92,0.08); }",
  ".sl-dragging { opacity:0.4; }",
  ".sl-drag-handle { opacity:0.3; font-size:1.2em; cursor:grab; transition:opacity 0.15s; }",
  ".sl-drag-handle:hover { opacity:0.7; }",
  ".sl-drag-handle:active { cursor:grabbing; }",
  ".sl-drag-indicator { height:3px; background:#00a3cc; border-radius:2px; margin:2px 0;",
  "  box-shadow:0 0 6px rgba(0,163,204,0.6); pointer-events:none; }",
  ".sl-expand-btn { cursor:pointer; width:28px; text-align:center; user-select:none; font-size:2.8em; line-height:1; transition:transform 0.15s; }",
  ".sl-expand-btn:hover { color:#00a3cc; }",
  ".sl-source-url { flex:1; font-size:0.9em; word-break:break-all; cursor:pointer; transition:color 0.15s; }",
  ".sl-source-url:hover { color:#00a3cc; }",
  ".sl-server-count { opacity:0.6; font-size:0.85em; white-space:nowrap; }",
  ".sl-source-time { opacity:0.5; font-size:0.85em; white-space:nowrap; }",
  ".sl-priority { opacity:0.3; font-size:0.85em; white-space:nowrap; margin-left:auto; }",

  /* Icon buttons */
  ".sl-icon-btn { padding:2px 6px !important; font-size:0.9em !important; margin:0 !important; min-width:34px; text-align:center; }",
  ".sl-icon-btn:hover:not(:disabled) { opacity:0.8; }",
  ".sl-spin-icon { animation:sl-spin 1s linear infinite; display:inline-block; }",
  "@keyframes sl-spin { from{transform:rotate(0)} to{transform:rotate(360deg)} }",

  /* Danger button */
  ".sl-btn-danger { color:#d9534f; }",

  /* VPN table */
  ".sl-vpn-container { margin:0 0 5px 0; border:1px solid var(--cbi-color-border,#ccc); border-radius:8px; padding:10px; }",
  ".sl-hidden { display:none; }",
  ".sl-vpn-table { width:100%; font-size:0.9em; table-layout:fixed; border-collapse:collapse; }",
  ".sl-th { padding:5px 8px; text-align:left; cursor:pointer; user-select:none; white-space:nowrap; opacity:0.6;",
  "  border-bottom:1px solid var(--cbi-color-border,#ccc); }",
  ".sl-th-active { opacity:1; font-weight:bold; }",
  ".sl-sort-arrow { font-size:0.8em; opacity:0.6; margin-left:2px; }",
  ".sl-row-selected td { background:rgba(92,184,92,0.25) !important; }",
  ".sl-td-name { padding:5px 8px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }",
  ".sl-td-ping { padding:5px 8px; white-space:nowrap; width:70px; }",
  ".sl-td-metric { padding:5px 8px; white-space:nowrap; width:60px; }",
  ".sl-td-action { padding:5px 8px; width:90px; text-align:right; }",
  ".sl-bold { font-weight:bold; }",
  ".sl-select-btn { padding:2px 10px !important; font-size:0.85em !important; margin:0 !important; min-width:70px; text-align:center; white-space:nowrap; }",
  ".sl-btn-active { background:#5cb85c !important; color:#ffffff !important; border-color:#4cae4c !important; opacity:1 !important; text-shadow:none !important; }",

  /* Color classes */
  ".sl-ok { color:#5cb85c; }",
  ".sl-warn { color:#f0ad4e; }",
  ".sl-bad { color:#d9534f; }",
  ".sl-ping-fast { color:#3cb371; }",
  ".sl-ping-good { color:#5cb85c; }",
  ".sl-ping-ok { color:#8ab550; }",
  ".sl-ping-slow { color:#f0ad4e; }",
  ".sl-ping-bad { color:#d9534f; }",

  /* Add row */
  ".sl-add-row { display:flex; gap:8px; margin-top:14px; align-items:center; }",
  "#tab-content-sources .sl-add-url { flex:1; padding:8px 12px !important; font-size:0.9em !important; min-width:300px; box-sizing:border-box;",
  "  height:39px !important; line-height:21px !important; }",

  /* Bottom bar */
  ".sl-bottom-bar { display:flex; justify-content:flex-end; gap:8px; margin-top:14px; }",
  ".sl-add-row .cbi-button-add, .sl-bottom-bar .cbi-button-save { min-width:110px; }",

  /* Empty/alert */
  ".sl-empty { padding:10px; opacity:0.5; font-size:0.9em; }",
  ".sl-alert { margin:14px 0; padding:12px; border:1px solid #f0ad4e; border-radius:8px; background:rgba(240,173,78,0.1); }",

  /* Toast */
  ".sl-toast { position:fixed; bottom:20px; right:20px; padding:10px 20px; border-radius:8px;",
  "  background:#333; color:#fff; font-size:0.9em; z-index:9999; opacity:0;",
  "  transition:opacity 0.3s, transform 0.3s; transform:translateY(10px); }",
  ".sl-toast-show { opacity:1; transform:translateY(0); }",
  ".sl-toast-ok { background:#5cb85c; }",
  ".sl-toast-err { background:#d9534f; }",

  /* Settings tab */
  "#tab-content-settings .cbi-section-node { padding:0 !important; }",
  "#tab-content-settings table { font-size:0.9em; }",
  "#tab-content-settings .cbi-value { padding:3px 0 !important; align-items:flex-start !important; display:flex !important; }",
  "#tab-content-settings .cbi-value-title { width:150px !important; flex-basis:150px !important; flex-grow:0 !important;",
  "  flex-shrink:0 !important; min-width:150px !important; padding:11px 8px 0 0 !important; line-height:1.5 !important; font-size:0.9em; }",
  "#tab-content-settings .cbi-value:has(.cbi-checkbox) .cbi-value-title { padding-top:2px !important; }",
  "#tab-content-settings .cbi-value-field { padding:2px 0 !important; margin:0 !important; flex:1; }",
  "#tab-content-settings .cbi-checkbox { line-height:0 !important; }",
  "#tab-content-settings .cbi-checkbox input[type=checkbox] { margin-top:0 !important; }",
  "#tab-content-settings input.cbi-input-text { width:200px !important; max-width:100%; }",
  "#tab-content-settings .cbi-dropdown { width:200px !important; max-width:100%; }",
  "#tab-content-settings .cbi-dvalue { padding:0 !important; }",
  ".sl-section { margin:0 0 16px 0; padding:14px 18px; border:1px solid var(--cbi-color-border,#ccc);",
  "  border-radius:8px; }",
  ".sl-section-title { font-size:0.9em; font-weight:bold; margin:0 0 10px 0;",
  "  padding-bottom:8px; border-bottom:1px solid var(--cbi-color-border,#ccc); }",
  "#tab-content-settings .cbi-section { margin:0 !important; border:none !important; box-shadow:none !important; padding:0 !important; }",

  /* About tab */
  ".sl-about-grid { display:grid; grid-template-columns:1fr 1fr; gap:16px; margin-top:14px; }",
  ".sl-about-card { border:1px solid var(--cbi-color-border,#ccc); border-radius:8px; padding:14px 18px; }",
  ".sl-about-card-title { font-size:0.8em; text-transform:uppercase; letter-spacing:1px; opacity:0.5; margin-bottom:10px; }",
  ".sl-about-row { display:flex; align-items:center; gap:8px; padding:6px 0; border-bottom:1px solid var(--cbi-color-border,#ccc); }",
  ".sl-about-row:last-child { border-bottom:none; }",
  ".sl-about-label { opacity:0.6; min-width:120px; font-size:0.9em; }",
  ".sl-about-value { font-weight:600; font-size:0.9em; }",
  ".sl-about-hero { text-align:center; padding:20px 0 16px; }",
  ".sl-about-hero-title { font-size:1.6em; font-weight:700; margin-bottom:8px; }",
  ".sl-about-hero-desc { font-size:0.9em; opacity:0.6; max-width:560px; margin:0 auto; line-height:1.5; }",
  ".sl-about-footer { display:flex; justify-content:center; flex-wrap:wrap; gap:10px; margin-top:20px; padding-top:16px;",
  "  border-top:1px solid var(--cbi-color-border,#ccc); }",
  ".sl-about-link { display:inline-flex; align-items:center; gap:6px; color:#00a3cc; text-decoration:none;",
  "  font-size:0.9em; padding:6px 16px; border:1px solid rgba(0,163,204,0.3); border-radius:8px; transition:all 0.15s; }",
  ".sl-about-link:hover { background:rgba(0,163,204,0.1); border-color:#00a3cc; }",
  ".sl-about-bar { height:6px; border-radius:3px; background:rgba(128,128,128,0.2); overflow:hidden; margin-top:4px; }",
  ".sl-about-bar-fill { height:100%; border-radius:3px; transition:width 0.3s; }",
  ".sl-about-mem-row { padding:6px 0; }",
  ".sl-about-mem-label { display:flex; justify-content:space-between; font-size:0.9em; }",
  "@media(max-width:640px) { .sl-about-grid { grid-template-columns:1fr; } }",
];

function injectCSS() {
  var style = el("style", {}, [CSS.join("\n")]);
  document.head.appendChild(style);
}

/* ============================================================ */
/* View                                                         */
/* ============================================================ */

var SmartlinkView = view.extend({
  load: function () {
    return Promise.all([api.status(), api.sources()]).then(function (r) {
      return { status: r[0], sources: r[1] };
    });
  },

  render: function (data) {
    injectCSS();

    state.sources = (data && data.sources && data.sources.sources) || [];
    state.proxies = (data && data.status && data.status.proxies) || [];
    state.current = (data && data.status && data.status.current) || null;
    state.lastUpdate = (data && data.status && data.status.last_update) || 0;

    // Settings form — options in fixed order, grouped after render
    var m = new form.Map("podkop-smartlink");
    var s = m.section(form.NamedSection, "main", "smartlink");
    s.addremove = false;
    var o;

    // Group 1: General (3 fields)
    o = s.option(form.ListValue, "update_interval", t("updateInterval"));
    o.value("30m", "30 " + (LANG === "ru" ? "мин" : "min"));
    o.value("1h", "1 " + (LANG === "ru" ? "ч" : "h"));
    o.value("3h", "3 " + (LANG === "ru" ? "ч" : "h"));
    o.value("6h", "6 " + (LANG === "ru" ? "ч" : "h"));
    o.value("12h", "12 " + (LANG === "ru" ? "ч" : "h"));
    o.value("24h", "24 " + (LANG === "ru" ? "ч" : "h"));
    o.default = "6h"; o.rmempty = false;
    o.description = t("updateIntervalDesc");

    o = s.option(form.Flag, "xhttp", t("xhttp"));
    o.rmempty = false;
    o.description = t("xhttpDesc");

    o = s.option(form.Flag, "use_priority", t("usePriority"));
    o.rmempty = false;
    o.description = t("usePriorityDesc");

    // Group 2: Selected VPN (3 fields)
    o = s.option(form.Value, "check_interval", t("checkInterval"));
    o.default = "10"; o.rmempty = false;
    o.datatype = "and(uinteger,min(5),max(300))";
    o.description = t("checkIntervalDesc");

    o = s.option(form.Value, "max_ping", t("maxPing"));
    o.default = "500"; o.rmempty = false;
    o.datatype = "and(uinteger,min(50),max(5000))";
    o.description = t("maxPingDesc");

    o = s.option(form.Value, "fail_count", t("failCount"));
    o.default = "3"; o.rmempty = false;
    o.datatype = "and(uinteger,min(1),max(20))";
    o.description = t("failCountDesc");

    // Group 3: All VPN (2 fields)
    o = s.option(form.Value, "ping_all_interval", t("pingAllInterval"));
    o.default = "60"; o.rmempty = false;
    o.datatype = "and(uinteger,min(15),max(600))";
    o.description = t("pingAllIntervalDesc");

    o = s.option(form.Value, "ping_timeout", t("pingTimeout"));
    o.default = "2000"; o.rmempty = false;
    o.datatype = "and(uinteger,min(500),max(30000))";
    o.description = t("pingTimeoutDesc");

    o = s.option(form.Value, "test_url", t("testUrl"));
    o.default = "http://cp.cloudflare.com/"; o.rmempty = false;
    o.description = t("testUrlDesc");

    // Sources container
    sourcesContainer = el("div", {});
    renderSources();

    var node = el("div", {});
    return m.render().then(function (formEl) {
      // Group fields into cards via DOM post-processing
      var groups = [
        { title: t("general"), count: 3 },
        { title: t("selectedVpn"), count: 3 },
        { title: t("allVpn"), count: 3 },
      ];
      var values = formEl.querySelectorAll(".cbi-value");
      if (values.length > 0) {
        var parent = values[0].parentNode;
        var idx = 0;
        groups.forEach(function (g) {
          if (idx >= values.length) return;
          var card = el("div", { class: "sl-section" }, [
            el("div", { class: "sl-section-title" }, [g.title]),
          ]);
          parent.insertBefore(card, values[idx]);
          for (var j = 0; j < g.count && idx < values.length; j++) {
            card.appendChild(values[idx]);
            idx++;
          }
        });
      }

      // About tab content
      var aboutContainer = el("div", { class: "sl-sources-tab" });
      api.getInfo().then(function (info) {
        if (!info || info.error) {
          aboutContainer.appendChild(el("div", { class: "sl-section" }, [
            el("div", { class: "sl-about-hero" }, [
              el("div", { class: "sl-about-hero-title" }, [t("aboutTitle")]),
              el("div", { class: "sl-about-hero-desc" }, [t("aboutDesc")]),
            ]),
          ]));
          return;
        }

        var slVer = info.smartlink || "—";
        var pkVer = info.podkop || "—";
        var sbVer = info.singbox || "—";
        var owrtVer = info.openwrt || "—";
        var uptimeStr = info.uptime || "—";
        var arch = info.arch || "—";
        var kernel = info.kernel || "—";
        var memTotal = (info.mem_total || 0);
        var memFree = (info.mem_free || 0);
        var memUsed = memTotal - memFree;
        var memPct = memTotal > 0 ? Math.round((memUsed / memTotal) * 100) : 0;
        var load = info.loadavg || "—";

        aboutContainer.appendChild(el("div", { class: "sl-section" }, [
          el("div", { class: "sl-about-hero" }, [
            el("div", { class: "sl-about-hero-title" }, ["Podkop SmartLink"]),
            el("div", { class: "sl-about-hero-desc" }, [t("aboutDesc")]),
          ]),
          el("div", { class: "sl-about-grid" }, [
            el("div", { class: "sl-about-card" }, [
              el("div", { class: "sl-about-card-title" }, [t("aboutProject")]),
              el("div", { class: "sl-about-row" }, [
                el("span", { class: "sl-about-label" }, ["SmartLink"]),
                el("span", { class: "sl-about-value" }, [slVer]),
              ]),
              el("div", { class: "sl-about-row" }, [
                el("span", { class: "sl-about-label" }, ["Podkop"]),
                el("span", { class: "sl-about-value" }, [pkVer]),
              ]),
              el("div", { class: "sl-about-row" }, [
                el("span", { class: "sl-about-label" }, ["sing-box"]),
                el("span", { class: "sl-about-value" }, [sbVer]),
              ]),
            ]),
            el("div", { class: "sl-about-card" }, [
              el("div", { class: "sl-about-card-title" }, [t("aboutSystem")]),
              el("div", { class: "sl-about-row" }, [
                el("span", { class: "sl-about-label" }, ["OpenWrt"]),
                el("span", { class: "sl-about-value" }, [owrtVer]),
              ]),
              el("div", { class: "sl-about-row" }, [
                el("span", { class: "sl-about-label" }, [t("aboutKernel")]),
                el("span", { class: "sl-about-value" }, [kernel]),
              ]),
              el("div", { class: "sl-about-row" }, [
                el("span", { class: "sl-about-label" }, [t("aboutArch")]),
                el("span", { class: "sl-about-value" }, [arch]),
              ]),
              el("div", { class: "sl-about-row" }, [
                el("span", { class: "sl-about-label" }, [t("uptime")]),
                el("span", { class: "sl-about-value" }, [uptimeStr]),
              ]),
              el("div", { class: "sl-about-row" }, [
                el("span", { class: "sl-about-label" }, [t("aboutLoad")]),
                el("span", { class: "sl-about-value" }, [load]),
              ]),
            ]),
          ]),
          el("div", { class: "sl-about-card", style: "margin-top:16px;" }, [
            el("div", { class: "sl-about-card-title" }, [t("aboutMemory")]),
            el("div", { class: "sl-about-mem-row" }, [
              el("div", { class: "sl-about-mem-label" }, [
                el("span", [], [t("aboutUsed") + " / " + t("aboutFree")]),
                el("span", [], [memUsed + " / " + memFree + " KB (" + memPct + "%)"]),
              ]),
              el("div", { class: "sl-about-bar" }, [
                el("div", { class: "sl-about-bar-fill", style: "width:" + memPct + "%; background:" + (memPct > 80 ? "#e74c3c" : memPct > 60 ? "#f39c12" : "#5cb85c") + ";" }),
              ]),
            ]),
          ]),
          el("div", { class: "sl-about-footer" }, [
            el("a", { class: "sl-about-link", href: "https://github.com/CriDos/podkop-smartlink", target: "_blank" }, ["GitHub"]),
            el("a", { class: "sl-about-link", href: "https://github.com/itdoginfo/podkop", target: "_blank" }, [t("aboutPodkop")]),
            el("a", { class: "sl-about-link", href: "https://github.com/CriDos/podkop-smartlink/issues", target: "_blank" }, [t("aboutIssues")]),
          ]),
        ]));
      });

      var tabWrap = createTabs(formEl, sourcesContainer, aboutContainer);
      node.appendChild(tabWrap);

      // Hide standard LuCI page actions if starting on Sources tab
      if (state.activeTab !== "settings") {
        setTimeout(function () {
          document.querySelectorAll(".cbi-page-actions").forEach(function (a) { a.style.display = "none"; });
        }, 0);
      }

      return node;
    });
  },
});

return SmartlinkView;
