// Reading logic, ported 1:1 from Sources/OdakCore (Tokenizer, Timing, ReaderEngine).
// "Characters" are grapheme clusters, like Swift's Character.

export const Timing = {
  sentenceEnd: 2.2,
  clause: 1.5,
  paragraphEnd: 2.5,
  longWordBonus: 0.3, // > longWordLetters
  veryLongWordBonus: 0.6, // > veryLongWordLetters
  longWordLetters: 8,
  veryLongWordLetters: 12,
  minWPM: 100,
  maxWPM: 1500,
  slowStartRamp: [2.0, 1.7, 1.45, 1.25, 1.1],
};

/** Extra delay factor for the first words after play starts. */
export const slowStartMultiplier = (wordsSincePlay) => Timing.slowStartRamp[wordsSincePlay] ?? 1;

/** FNV-1a 32-bit hash of the UTF-16 code units, as 8 hex digits. Identifies a text for resuming. */
export function textHash(text) {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 0x01000193);
  return (h >>> 0).toString(16).padStart(8, "0");
}

const sentenceEnders = new Set([".", "!", "?", "…"]);
const clauseEnders = new Set([",", ";", ":"]);
const closers = new Set(['"', "'", ")", "]", "}", "”", "’", "»"]);
const segmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });

export const graphemes = (s) => Array.from(segmenter.segment(s), (g) => g.segment);
// Swift's Character.isLetter/isNumber look at the first scalar of the cluster.
export const isWordCharacter = (c) => /^[\p{L}\p{N}]/u.test(c);

/** Last character ignoring closing quotes/brackets, e.g. `end."` -> `.` */
function lastMeaningful(chars) {
  for (let i = chars.length - 1; i >= 0; i--) if (!closers.has(chars[i])) return chars[i];
  return undefined;
}

export function endsSentence(word) {
  return sentenceEnders.has(lastMeaningful(graphemes(word)));
}

export function multiplier(word, endsParagraph) {
  const chars = graphemes(word);
  let base = 1;
  if (endsParagraph) base = Timing.paragraphEnd;
  else if (sentenceEnders.has(lastMeaningful(chars))) base = Timing.sentenceEnd;
  else if (clauseEnders.has(lastMeaningful(chars))) base = Timing.clause;

  const letters = chars.filter(isWordCharacter).length;
  if (letters > Timing.veryLongWordLetters) base += Timing.veryLongWordBonus;
  else if (letters > Timing.longWordLetters) base += Timing.longWordBonus;
  return base;
}

/** Optimal recognition point: index (in characters) of the character to highlight. */
export function orpIndex(word) {
  const chars = graphemes(word);
  // Count word characters, not positions, so the highlight never lands on "'" or "." inside a word.
  const wordIndices = chars.flatMap((c, i) => (isWordCharacter(c) ? [i] : []));
  if (wordIndices.length === 0) return 0;
  const n = wordIndices.length;
  const offset = n <= 1 ? 0 : n <= 5 ? 1 : n <= 9 ? 2 : n <= 13 ? 3 : 4;
  return wordIndices[offset] ?? wordIndices[n - 1];
}

/** Text before, at and after the ORP character. */
export function parts(token) {
  const chars = graphemes(token.text);
  if (chars.length === 0) return { left: "", orp: "", right: "" };
  const i = token.orpIndex;
  return { left: chars.slice(0, i).join(""), orp: chars[i], right: chars.slice(i + 1).join("") };
}

// Same separators as Swift's Character.isNewline / isWhitespace.
const newline = /\r\n|[\n\v\f\r\u0085\u2028\u2029]/;

/** Splits text into words. A blank line ends a paragraph; single line breaks are spaces (hard-wrapped text). */
export function tokenize(text) {
  const tokens = [];
  let sentence = 0;
  let startNewSentence = false;

  const markParagraphEnd = () => {
    const last = tokens.at(-1);
    if (!last || last.endsParagraph) return;
    last.delayMultiplier = multiplier(last.text, true);
    last.endsParagraph = true;
    startNewSentence = true;
  };

  for (const line of text.split(newline)) {
    // Split on grapheme clusters like Swift: a space plus trailing combining marks is one whitespace Character.
    const words = [];
    let w = "";
    for (const g of graphemes(line)) {
      if (/^\p{White_Space}/u.test(g)) {
        if (w) words.push(w);
        w = "";
      } else w += g;
    }
    if (w) words.push(w);
    if (words.length === 0) {
      markParagraphEnd();
      continue;
    }
    for (const word of words) {
      if (startNewSentence) {
        sentence++;
        startNewSentence = false;
      }
      tokens.push({
        text: word,
        orpIndex: orpIndex(word),
        delayMultiplier: multiplier(word, false),
        sentenceIndex: sentence,
        endsParagraph: false,
      });
      if (endsSentence(word)) startNewSentence = true;
    }
  }
  markParagraphEnd();
  return tokens;
}

/** Playback state, like ReaderEngine. `onChange` runs after every change. */
export class Reader {
  tokens = [];
  index = 0;
  playing = false;
  wordsSincePlay = 0; // words shown since the last play(); seeking does not reset it
  #wpm = 300;
  #suffix = [0]; // #suffix[i] = sum of delay multipliers from token i to the end
  #timer = null;

  constructor(wpm = 300, onChange = () => {}) {
    this.wpm = wpm;
    this.onChange = onChange;
  }

  get wpm() { return this.#wpm; }
  set wpm(v) {
    this.#wpm = Math.min(Math.max(Math.round(v) || 0, Timing.minWPM), Timing.maxWPM);
    this.onChange?.();
  }

  get current() { return this.tokens[this.index]; }
  get progress() { return this.tokens.length ? (this.index + 1) / this.tokens.length : 0; }
  get secondsPerWord() { return 60 / this.#wpm; }
  get remainingTime() { return this.tokens.length ? this.#suffix[this.index] * this.secondsPerWord : 0; }
  get atEnd() { return this.index >= this.tokens.length - 1; }

  load(text) {
    this.pause();
    this.tokens = tokenize(text);
    this.#suffix = new Array(this.tokens.length + 1).fill(0);
    for (let i = this.tokens.length - 1; i >= 0; i--) this.#suffix[i] = this.#suffix[i + 1] + this.tokens[i].delayMultiplier;
    this.index = 0;
    this.onChange();
  }

  play() {
    if (this.playing || !this.tokens.length) return;
    if (this.atEnd) this.index = 0;
    this.playing = true;
    this.wordsSincePlay = 0;
    this.#schedule();
    this.onChange();
  }

  pause() {
    clearTimeout(this.#timer);
    this.#timer = null;
    if (!this.playing) return;
    this.playing = false;
    this.onChange();
  }

  toggle() { this.playing ? this.pause() : this.play(); }

  seek(i) {
    if (!this.tokens.length) return;
    this.index = Math.min(Math.max(i, 0), this.tokens.length - 1);
    this.onChange();
  }

  step(delta) { this.seek(this.index + delta); }

  /** Forward: start of next sentence (or last word). Backward: start of the current sentence,
   *  or of the previous one when already at a sentence start. */
  jumpSentence(forward) {
    const current = this.current;
    if (!current) return;
    if (forward) {
      const next = this.tokens.findIndex((t, i) => i >= this.index && t.sentenceIndex > current.sentenceIndex);
      this.seek(next === -1 ? this.tokens.length - 1 : next);
    } else {
      const start = this.#sentenceStart(this.index);
      this.seek(start === this.index && start > 0 ? this.#sentenceStart(start - 1) : start);
    }
  }

  restart() {
    const wasPlaying = this.playing;
    this.pause();
    this.index = 0;
    if (wasPlaying) this.play();
    else this.onChange();
  }

  // The delay is read when each word is shown, so speed changes apply from the next word on.
  #schedule() {
    this.#timer = setTimeout(() => {
      if (this.atEnd) return this.pause();
      this.index++;
      this.wordsSincePlay++;
      this.#schedule();
      this.onChange();
    }, this.current.delayMultiplier * this.secondsPerWord * slowStartMultiplier(this.wordsSincePlay) * 1000);
  }

  #sentenceStart(i) {
    const s = this.tokens[i].sentenceIndex;
    while (i > 0 && this.tokens[i - 1].sentenceIndex === s) i--;
    return i;
  }
}

/** Seconds as m:ss. */
export function formatTime(seconds) {
  const s = Math.round(seconds);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}
