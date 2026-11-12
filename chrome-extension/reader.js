import { Reader, parts, formatTime, Timing, textHash } from "./core.js";

const $ = (id) => document.getElementById(id);
const t = (key, ...subs) => chrome.i18n.getMessage(key, subs.map(String));
const word = $("word"), progress = $("progress"), stage = $("stage");
const playback = [$("toggle"), $("prev"), $("next"), $("restart")];
const themes = ["charcoal", "midnight", "sepia", "paper"];
const themeNames = { charcoal: "themeCharcoal", midnight: "themeMidnight", sepia: "themeSepia", paper: "themePaper" };
const font = { min: 24, max: 140, step: 4 };
const neighbours = 3, contextTokens = 150;

const label = (el, key) => {
  el.setAttribute("aria-label", t(key));
  el.title = t(key);
};
document.documentElement.lang = chrome.i18n.getUILanguage();
word.setAttribute("aria-label", t("currentWord"));
progress.setAttribute("aria-label", t("readingProgress"));
$("wpm-group").setAttribute("aria-label", t("wordsPerMinute"));
$("font-group").setAttribute("aria-label", t("fontSize"));
$("wpm-name").textContent = t("wpmLabel");
$("font-name").textContent = t("fontSize");
$("hint").textContent = t("startHint");
label($("wpm-up"), "faster");
label($("wpm-down"), "slower");
label($("font-up"), "largerText");
label($("font-down"), "smallerText");
label($("prev"), "previousSentence");
label($("next"), "nextSentence");
label($("restart"), "restart");
label($("fullscreen"), "fullScreen");

const reader = new Reader(300, render);
const measure = document.createElement("canvas").getContext("2d");
let baseFontSize = 64, theme = "charcoal", started = false, wasPlaying = false, idleTimer;
let hash = null, resumeIndex = 0, positions = {}; // resumeIndex: where this text was restored to, 0 if not resumed

function render() {
  const token = reader.current;
  const { left, orp, right } = token ? parts(token) : { left: "", orp: "", right: "" };
  $("cur-left").textContent = left;
  $("orp").textContent = orp;
  $("cur-right").textContent = right;
  word.style.fontSize = fittedSize(left, orp, right) + "px";
  word.setAttribute("aria-label", token?.text ?? t("currentWord"));
  // Context only changes while paused; while playing it is faded out and left as is.
  if (!reader.playing) renderContext();
  $("hint").hidden = started || reader.index !== resumeIndex;

  const count = reader.tokens.length;
  const position = count ? reader.index + 1 : 0;
  const percent = reader.progress * 100 + "%";
  $("fill").style.width = percent;
  $("thumb").style.left = percent;
  progress.setAttribute("aria-valuemax", count);
  progress.setAttribute("aria-valuenow", position);
  progress.setAttribute("aria-valuetext", t("wordOf", position, count));
  const seconds = reader.remainingTime;
  $("remaining").textContent = seconds < 60 ? t("underAMinute") : t("minutes", Math.ceil(seconds / 60));
  $("remaining").title = `${t("timeLeft", formatTime(seconds))}\n${t("wordOf", position, count)}`;

  $("play-icon").hidden = reader.playing;
  $("pause-icon").hidden = !reader.playing;
  label($("toggle"), reader.playing ? "pause" : "play");
  $("wpm-value").textContent = reader.wpm;
  $("font-value").textContent = baseFontSize;
  $("wpm-up").disabled = reader.wpm >= Timing.maxWPM;
  $("wpm-down").disabled = reader.wpm <= Timing.minWPM;
  $("font-up").disabled = baseFontSize >= font.max;
  $("font-down").disabled = baseFontSize <= font.min;
  const name = t(themeNames[theme]);
  $("theme").setAttribute("aria-label", t("theme", name));
  $("theme").title = t("theme", name);

  if (reader.playing !== wasPlaying) {
    wasPlaying = reader.playing;
    if (reader.playing) started = true;
    else savePosition();
    document.body.classList.toggle("playing", reader.playing);
    wake();
  }
}

/** Words joined with spaces, with a blank line after paragraph ends. */
const joined = (tokens) => tokens.map((x) => x.text + (x.endsParagraph ? "\n\n" : " ")).join("").trimEnd();

function renderContext() {
  const i = reader.index, tokens = reader.tokens;
  // The gap is a text space, not padding: padding can't shrink and would clip a fitted current word.
  const prev = joined(tokens.slice(Math.max(i - neighbours, 0), i)), next = joined(tokens.slice(i + 1, i + 1 + neighbours));
  $("prev-words").firstChild.textContent = prev && prev + "\u00a0";
  $("next-words").textContent = next && "\u00a0" + next;
  $("before").textContent = joined(tokens.slice(Math.max(i - neighbours - contextTokens, 0), Math.max(i - neighbours, 0)));
  $("after-text").textContent = joined(tokens.slice(i + 1 + neighbours, i + 1 + neighbours + contextTokens));
}

/** Font size at which the longer half of the current word still fits its half of the width. Neighbours don't count. */
function fittedSize(left, orp, right) {
  const style = getComputedStyle(word);
  measure.font = `${style.fontWeight} ${baseFontSize}px ${style.fontFamily}`;
  const w = (s) => measure.measureText(s).width;
  const needed = 2 * Math.max(w(left), w(right)) + w(orp);
  const width = word.clientWidth;
  // Text width scales linearly with font size; 0.97 leaves room for rounding.
  return needed > width ? (baseFontSize * width * 0.97) / needed : baseFontSize;
}

/** Shows the toolbars; while playing they fade out again after 1.5 s without pointer movement. */
function wake() {
  document.body.classList.remove("idle");
  clearTimeout(idleTimer);
  if (reader.playing) idleTimer = setTimeout(() => document.body.classList.add("idle"), 1500);
}
document.addEventListener("pointermove", wake);

function setFontSize(size) {
  baseFontSize = Math.min(Math.max(size, font.min), font.max);
  document.documentElement.style.setProperty("--font", baseFontSize + "px");
  render();
}

function setTheme(name) {
  theme = themes.includes(name) ? name : "charcoal";
  document.documentElement.dataset.theme = theme;
  render();
}

function showMessage(text) {
  stage.hidden = true;
  $("message").hidden = false;
  $("message").textContent = text;
  for (const el of playback) el.disabled = true;
  progress.removeAttribute("tabindex");
}

const changeWpm = (delta) => {
  reader.wpm += delta;
  chrome.storage.local.set({ wpm: reader.wpm });
};
// Anywhere but the toolbars, including the margins beside the 900px text column.
document.body.onclick = (e) => e.target.closest(".toolbar") || reader.toggle();
$("toggle").onclick = () => reader.toggle();
$("prev").onclick = () => reader.jumpSentence(false);
$("next").onclick = () => reader.jumpSentence(true);
$("restart").onclick = () => reader.restart();
$("wpm-up").onclick = () => changeWpm(25);
$("wpm-down").onclick = () => changeWpm(-25);
$("font-up").onclick = () => chrome.storage.local.set({ fontSize: baseFontSize + font.step });
$("font-down").onclick = () => chrome.storage.local.set({ fontSize: baseFontSize - font.step });
$("theme").onclick = () => chrome.storage.local.set({ theme: themes[(themes.indexOf(theme) + 1) % themes.length] });
$("fullscreen").onclick = () =>
  document.fullscreenElement ? document.exitFullscreen() : document.documentElement.requestFullscreen();
// Applies changes from these buttons and from other open reader windows.
chrome.storage.onChanged.addListener((changes, area) => {
  if (area !== "local") return;
  if (changes.fontSize) setFontSize(changes.fontSize.newValue);
  if (changes.theme) setTheme(changes.theme.newValue);
});

function seekTo(event) {
  const rect = progress.getBoundingClientRect();
  const fraction = Math.min(Math.max((event.clientX - rect.left) / Math.max(rect.width, 1), 0), 1);
  reader.seek(Math.floor(fraction * reader.tokens.length));
}
progress.onpointerdown = (e) => {
  if (!reader.tokens.length) return;
  progress.setPointerCapture(e.pointerId);
  seekTo(e);
};
progress.onpointermove = (e) => progress.hasPointerCapture(e.pointerId) && seekTo(e);

document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && !document.fullscreenElement) return window.close();
  if (!reader.tokens.length || e.ctrlKey || e.metaKey) return;
  const before = reader.wpm;
  switch (e.key) {
    // Only arrows auto-repeat; holding Space/R must not keep toggling.
    case " ": if (!e.repeat) reader.toggle(); break;
    case "r": case "R": if (!e.repeat) reader.restart(); break;
    case "ArrowLeft": e.altKey ? reader.jumpSentence(false) : reader.step(-1); break;
    case "ArrowRight": e.altKey ? reader.jumpSentence(true) : reader.step(1); break;
    case "ArrowUp": reader.wpm += 25; break;
    case "ArrowDown": reader.wpm -= 25; break;
    default: return;
  }
  // Also stops focused buttons/slider from acting on the same key.
  e.preventDefault();
  if (reader.wpm !== before) chrome.storage.local.set({ wpm: reader.wpm });
});

const maxPositions = 20;
/** Remembers where this text was left, keeping the 20 most recent texts. */
// Writes synchronously from the copy read at load, so it still lands on pagehide.
// shortcut: two reader windows open at once can drop each other's newest entry, re-read storage if that matters.
function savePosition() {
  if (!hash || !reader.tokens.length) return;
  positions[hash] = { index: reader.index, savedAt: Date.now() };
  const recent = Object.entries(positions).sort((a, b) => b[1].savedAt - a[1].savedAt).slice(0, maxPositions);
  positions = Object.fromEntries(recent);
  chrome.storage.local.set({ positions });
}
addEventListener("pagehide", savePosition);
document.addEventListener("visibilitychange", () => document.visibilityState === "hidden" && savePosition());

new ResizeObserver(render).observe(word);

const id = new URLSearchParams(location.search).get("id") ?? "";
const [{ [id]: stored }, { wpm = 300, fontSize = 64, theme: savedTheme, positions: savedPositions }] = await Promise.all([
  chrome.storage.session.get(id),
  chrome.storage.local.get(["wpm", "fontSize", "theme", "positions"]),
]);
chrome.storage.session.remove(id);
// sessionStorage survives a reload of this window and is gone when it closes.
const payload = stored ?? JSON.parse(sessionStorage.getItem(id) ?? "null");
try {
  sessionStorage.setItem(id, JSON.stringify(payload));
} catch {} // shortcut: text over the ~5 MB sessionStorage quota is lost on reload, store chunks if that matters
reader.wpm = wpm;
setTheme(savedTheme);
setFontSize(fontSize);
reader.load(payload?.text ?? "");
positions = savedPositions ?? {};
if (reader.tokens.length) {
  hash = textHash(payload.text);
  const saved = positions[hash]?.index;
  // Resume paused where this text was left, unless it was read to the end.
  if (saved > 0 && saved < reader.tokens.length - 1) {
    resumeIndex = saved;
    $("hint").textContent = t("continueHint");
    reader.seek(saved);
  }
}
// Starts paused at the first word; a click on the reading area or Space starts reading.
if (payload?.error || !reader.tokens.length) showMessage(t(payload?.error ?? "errorNoText"));
