"use strict";

const POLL_MS = 2500;
const $ = (id) => document.getElementById(id);
let state = null;
let editingId = null;

// ---------- API ----------
async function api(method, path, body) {
  const res = await fetch(path, {
    method,
    headers: body ? { "Content-Type": "application/json" } : {},
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok && res.status !== 304) {
    let msg = `Error ${res.status}`;
    try { msg = (await res.json()).error || msg; } catch {}
    throw new Error(msg);
  }
  return res.status === 200 || res.status === 201 ? res.json() : null;
}

async function refresh() {
  try {
    state = await api("GET", "/api/state?player=1");
    $("offline").hidden = true;
    render();
  } catch {
    $("offline").hidden = false;
  }
}

async function act(fn) {
  try { await fn(); } catch (e) { alert(e.message); }
  refresh();
}

// ---------- helpers ----------
const keyLabel = (k) => (k > 0 ? `+${k}` : k < 0 ? `−${-k}` : "Original");
const time = (ms) => {
  const s = Math.max(0, Math.floor(ms / 1000));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
};

function setStepper(output, value) {
  const v = Math.max(-6, Math.min(6, value));
  output.dataset.value = v;
  output.textContent = v === 0 ? "Original" : `Key ${keyLabel(v)}`;
}

document.querySelectorAll(".stepper").forEach((s) => {
  const out = $(s.dataset.for);
  s.addEventListener("click", (e) => {
    const step = e.target.closest("button")?.dataset.step;
    if (step) setStepper(out, Number(out.dataset.value) + Number(step));
  });
});

// ---------- add ----------
const singerInput = $("singer");
try { singerInput.value = localStorage.getItem("singer") || ""; } catch {}
// Remembered as soon as it's typed, not only when a song is added.
singerInput.addEventListener("change", () => {
  try { localStorage.setItem("singer", singerInput.value.trim()); } catch {}
});

if (navigator.clipboard?.readText) {
  $("paste").hidden = false;
  $("paste").addEventListener("click", async () => {
    try { $("url").value = (await navigator.clipboard.readText()).trim(); } catch {}
  });
}

$("add").addEventListener("submit", async (e) => {
  e.preventDefault();
  if (!$("url").value.trim()) { $("url").focus(); return; }
  const btn = $("addBtn");
  const err = $("addError");
  err.hidden = true;
  btn.disabled = true;
  try {
    const singer = singerInput.value.trim();
    try { localStorage.setItem("singer", singer); } catch {}
    await api("POST", "/api/queue", {
      url: $("url").value.trim(),
      singer,
      key: Number($("addKey").dataset.value),
    });
    $("url").value = "";
    setStepper($("addKey"), 0);
    btn.textContent = "Added ✓";
    setTimeout(() => (btn.textContent = "Add to queue"), 1500);
  } catch (ex) {
    err.textContent = ex.message;
    err.hidden = false;
  } finally {
    btn.disabled = false;
    refresh();
  }
});

// ---------- search ----------
$("searchForm").addEventListener("submit", async (e) => {
  e.preventDefault();
  const q = $("q").value.trim();
  if (!q) return;
  $("q").blur();
  const status = $("searchStatus");
  status.hidden = false;
  status.textContent = "Searching…";
  $("results").replaceChildren();
  try {
    const karaoke = $("karaoke").checked ? 1 : 0;
    const { results } = await api("GET", `/api/search?q=${encodeURIComponent(q)}&karaoke=${karaoke}`);
    status.hidden = results.length > 0;
    status.textContent = "No songs found. Try different words.";
    $("results").replaceChildren(...results.map(resultRow));
  } catch (ex) {
    status.textContent = ex.message;
  }
});

function resultRow(r) {
  const li = $("result").content.firstElementChild.cloneNode(true);
  const img = li.querySelector(".thumb");
  if (r.thumb) img.src = r.thumb; else img.removeAttribute("src");
  li.querySelector(".title").textContent = r.title;
  li.querySelector(".channel").textContent = r.channel || "";
  li.querySelector(".len").textContent = r.durationSec ? time(r.durationSec * 1000) : "";
  const btn = li.querySelector(".add-result");
  btn.onclick = async () => {
    btn.disabled = true;
    try {
      const singer = singerInput.value.trim();
      try { localStorage.setItem("singer", singer); } catch {}
      await api("POST", "/api/queue", {
        url: r.url, title: r.title, channel: r.channel, thumb: r.thumb, durationSec: r.durationSec,
        singer, key: Number($("addKey").dataset.value),
      });
      btn.textContent = "Added ✓";
    } catch (ex) {
      btn.disabled = false;
      alert(ex.message);
    }
    refresh();
  };
  return li;
}

// ---------- render ----------
function render() {
  const { nowPlaying, player, queue, phase, upNext } = state;

  $("now").hidden = !nowPlaying;
  if (nowPlaying) {
    $("nowThumb").src = nowPlaying.thumb || "";
    $("nowSinger").textContent = nowPlaying.singer || "Someone";
    $("nowTitle").textContent = nowPlaying.title;
    const pos = player?.positionMs || 0, dur = player?.durationMs || 0;
    $("nowBar").style.width = dur ? `${(100 * pos) / dur}%` : "0";
    const key = player?.key ?? nowPlaying.presetKey;
    $("nowTime").textContent = dur
      ? `${time(pos)} / ${time(dur)} · ${key ? `Key ${keyLabel(key)}` : "Original key"}${player?.paused ? " · Paused" : ""}`
      : "Loading…";
  }

  const next = phase === "upnext" && queue.find((e) => e.id === upNext?.entryId);
  $("upnext").hidden = !next;
  if (next) $("upnext").textContent = `Starting in ${upNext.secondsLeft}: ${next.singer || "next singer"}`;

  $("count").textContent = queue.length ? `· ${queue.length}` : "";
  $("empty").hidden = queue.length > 0;

  const list = $("queue");
  list.replaceChildren(...queue.map((e, i) => row(e, i, queue.length)));
}

function row(e, i, n) {
  const li = $("row").content.firstElementChild.cloneNode(true);
  const img = li.querySelector(".thumb");
  if (e.thumb) img.src = e.thumb; else img.removeAttribute("src");
  li.querySelector(".title").textContent = e.title;
  li.querySelector(".singer").textContent = e.singer || "No name";
  const chip = li.querySelector(".key");
  if (e.presetKey) chip.textContent = `Key ${keyLabel(e.presetKey)}`; else chip.remove();
  const st = li.querySelector(".status");
  if (e.status === "RESOLVING") { st.className = "status resolving"; st.textContent = "Loading"; }
  else if (e.status === "ERROR") { st.className = "status error"; st.textContent = "Can't play"; st.title = e.error || ""; }
  else st.remove();

  const up = li.querySelector(".up"), down = li.querySelector(".down");
  up.disabled = i === 0;
  down.disabled = i === n - 1;
  up.onclick = () => act(() => api("POST", `/api/queue/${e.id}/move`, { index: i - 1 }));
  down.onclick = () => act(() => api("POST", `/api/queue/${e.id}/move`, { index: i + 1 }));
  li.querySelector(".remove").onclick = () => {
    if (confirm(`Remove “${e.title}”?`)) act(() => api("DELETE", `/api/queue/${e.id}`));
  };
  li.querySelector(".edit").onclick = () => openEdit(e);
  return li;
}

// ---------- edit ----------
function openEdit(e) {
  editingId = e.id;
  $("editTitle").textContent = e.title;
  $("editSinger").value = e.singer;
  setStepper($("editKey"), e.presetKey);
  $("editDialog").showModal();
}

$("editDialog").addEventListener("close", () => {
  if ($("editDialog").returnValue === "save" && editingId) {
    const id = editingId;
    act(() => api("PATCH", `/api/queue/${id}`, {
      singer: $("editSinger").value.trim(),
      key: Number($("editKey").dataset.value),
    }));
  }
  editingId = null;
});

refresh();
setInterval(() => { if (!document.hidden) refresh(); }, POLL_MS);
document.addEventListener("visibilitychange", () => { if (!document.hidden) refresh(); });

// ---------- reactions ----------
// The four buttons sit behind a Reactions button so they aren't pressed by accident, and fold
// away again after a few seconds without a press.
const REACTIONS_OPEN_MS = 5000;
// A short cooldown per button keeps one phone from flooding the TV with the same sound.
const REACTION_COOLDOWN_MS = 800;
const reactionsToggle = $("reactionsToggle");
const reactionButtons = $("reactionButtons");
let reactionsTimer = null;

function showReactions(open) {
  reactionButtons.hidden = !open;
  reactionsToggle.hidden = open;
  reactionsToggle.setAttribute("aria-expanded", String(open));
  clearTimeout(reactionsTimer);
  if (open) reactionsTimer = setTimeout(() => showReactions(false), REACTIONS_OPEN_MS);
}

reactionsToggle.addEventListener("click", () => showReactions(true));

document.querySelectorAll("[data-reaction]").forEach((button) => {
  let lastSent = 0;
  button.addEventListener("click", async () => {
    showReactions(true); // restarts the countdown
    const now = Date.now();
    if (now - lastSent < REACTION_COOLDOWN_MS) return;
    lastSent = now;
    button.classList.remove("sent", "failed");
    void button.offsetWidth; // restart the animation on repeat presses
    try {
      await api("POST", `/api/react/${button.dataset.reaction}`);
      button.classList.add("sent");
    } catch {
      button.classList.add("failed");
    }
    setTimeout(() => button.classList.remove("sent", "failed"), 600);
  });
});
