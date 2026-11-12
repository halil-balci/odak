// Mirrors Tests/OdakCoreTests. Run: node --test chrome-extension/tests/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { tokenize, orpIndex, multiplier, parts, isWordCharacter, graphemes, Timing, Reader, formatTime, slowStartMultiplier, textHash } from "../core.js";

const texts = (t) => t.map((x) => x.text);

test("empty and whitespace", () => {
  assert.deepEqual(tokenize(""), []);
  assert.deepEqual(tokenize("   \n\t \n\n  "), []);
});

test("collapses whitespace and keeps punctuation", () => {
  assert.deepEqual(texts(tokenize("  Hello,   world!\tHow\u00A0are you?  ")), ["Hello,", "world!", "How", "are", "you?"]);
});

test("space plus combining mark is one separator, like Swift", () => {
  assert.deepEqual(texts(tokenize("a ́ b")), ["a", "b"]);
  assert.deepEqual(texts(tokenize("x ‍ y")), ["x", "y"]);
  // A tab is a Control character and never absorbs extenders.
  assert.deepEqual(texts(tokenize("a\t́ b")), ["a", "́", "b"]);
});

test("punctuation only", () => {
  const t = tokenize("... — !!");
  assert.deepEqual(texts(t), ["...", "—", "!!"]);
  assert.ok(t.every((x) => x.orpIndex === 0));
});

test("em-dash joined word stays one token", () => {
  assert.deepEqual(texts(tokenize("word—word")), ["word—word"]);
});

test("Turkish unicode", () => {
  const t = tokenize("Çığ düştü, İstanbul'da şöyle böyle.");
  assert.deepEqual(texts(t), ["Çığ", "düştü,", "İstanbul'da", "şöyle", "böyle."]);
  assert.equal(parts(t[0]).orp, "ı");
  for (const x of t) assert.ok(x.orpIndex < graphemes(x.text).length);
});

test("sentences and paragraphs", () => {
  const t = tokenize("One two. Three!\nfour\n\n\nFive six");
  assert.deepEqual(texts(t), ["One", "two.", "Three!", "four", "Five", "six"]);
  assert.deepEqual(t.map((x) => x.sentenceIndex), [0, 0, 1, 2, 3, 3]);
  assert.deepEqual(t.map((x) => x.endsParagraph), [false, false, false, true, false, true]);
});

test("CRLF line breaks", () => {
  assert.deepEqual(tokenize("a\r\n\r\nb").map((x) => x.endsParagraph), [true, true]);
});

test("quoted sentence end", () => {
  const t = tokenize('He said "stop." Then left');
  assert.ok(t[2].sentenceIndex === 0 && t[3].sentenceIndex === 1);
});

test("ORP by length", () => {
  for (const [w, i] of [["a", 0], ["an", 1], ["hello", 1], ["reader", 2], ["wonderful", 2],
    ["comprehends", 3], ["understandings", 4], ["antidisestablishmentarianism", 4]]) {
    assert.equal(orpIndex(w), i, w);
  }
});

test("ORP offset by leading punctuation", () => {
  assert.equal(orpIndex('"hello"'), 2);
  assert.equal(orpIndex("(a)"), 1);
  assert.equal(orpIndex("«understandings»"), 5);
});

test("ORP lands on a word character", () => {
  for (const w of ["I'm", "O'nun", "U.S.", "e.g.", "a\u200Bb", "don't"]) {
    assert.ok(isWordCharacter(graphemes(w)[orpIndex(w)]), w);
  }
});

test("ORP never out of bounds", () => {
  const samples = ["", "a", ".", '"', "a.", "((x", "—", "x" + ".".repeat(20), "👍🏽ok", "e\u0301te\u0301"];
  for (let n = 1; n <= 40; n++) samples.push("x".repeat(n), '"' + "ğ".repeat(n) + '!"');
  for (const w of samples) {
    const i = orpIndex(w);
    assert.ok(i >= 0);
    if (w) assert.ok(i < graphemes(w).length, w);
  }
});

test("parts split around ORP", () => {
  assert.deepEqual(parts(tokenize("reading")[0]), { left: "re", orp: "a", right: "ding" });
});

test("multipliers", () => {
  assert.equal(multiplier("word", false), 1);
  assert.equal(multiplier("word.", false), Timing.sentenceEnd);
  assert.equal(multiplier("word?", false), Timing.sentenceEnd);
  assert.equal(multiplier("word…", false), Timing.sentenceEnd);
  assert.equal(multiplier("word,", false), Timing.clause);
  assert.equal(multiplier("word;", false), Timing.clause);
  assert.equal(multiplier("word:", false), Timing.clause);
  assert.equal(multiplier("word.", true), Timing.paragraphEnd);
  assert.equal(multiplier("wonderful", false), 1 + Timing.longWordBonus);
  assert.equal(multiplier("understandings", false), 1 + Timing.veryLongWordBonus);
  assert.equal(multiplier("understandings.", false), Timing.sentenceEnd + Timing.veryLongWordBonus);
});

test("tokenizer applies paragraph multiplier", () => {
  assert.deepEqual(tokenize("a b.\n\nc").map((x) => x.delayMultiplier), [1, Timing.paragraphEnd, Timing.paragraphEnd]);
});

const text = "One two three. Four five six. Seven eight.";

test("empty reader", () => {
  const e = new Reader();
  assert.ok(e.current === undefined && e.progress === 0 && e.remainingTime === 0);
  e.play(); e.step(1); e.jumpSentence(true); e.seek(5);
  assert.ok(!e.playing && e.index === 0);
});

test("wpm clamped", () => {
  const e = new Reader();
  e.wpm = 10; assert.equal(e.wpm, 100);
  e.wpm = 99999; assert.equal(e.wpm, 1500);
  assert.equal(new Reader(0).wpm, 100);
});

test("seek and step clamp", () => {
  const e = new Reader(); e.load(text);
  e.seek(-5); assert.equal(e.index, 0);
  e.seek(100); assert.equal(e.index, 7);
  e.step(1); assert.equal(e.index, 7);
  e.step(-3); assert.equal(e.index, 4);
  assert.equal(e.current.text, "five");
});

test("jump sentence", () => {
  const e = new Reader(); e.load(text);
  const jumps = [[true, 3], [true, 6], [true, 7], [false, 6], [false, 3]];
  for (const [fwd, i] of jumps) { e.jumpSentence(fwd); assert.equal(e.index, i); }
  e.seek(4); e.jumpSentence(false); assert.equal(e.index, 3);
  e.seek(0); e.jumpSentence(false); assert.equal(e.index, 0);
});

test("progress and remaining time", () => {
  const e = new Reader(600); e.load(text);
  assert.equal(e.progress, 1 / 8);
  const total = e.tokens.reduce((s, t) => s + t.delayMultiplier, 0) * 0.1;
  assert.ok(Math.abs(e.remainingTime - total) < 1e-9);
  e.seek(7);
  assert.equal(e.progress, 1);
  assert.ok(Math.abs(e.remainingTime - e.tokens[7].delayMultiplier * 0.1) < 1e-9);
});

test("plays to end and stops", async () => {
  const e = new Reader(1500); e.load("a b c");
  e.play();
  assert.ok(e.playing);
  for (let n = 0; n < 100 && e.playing; n++) await new Promise((r) => setTimeout(r, 20));
  assert.ok(!e.playing && e.index === 2);
  e.play(); // at end: restarts from the beginning
  assert.ok(e.playing && e.index === 0);
  e.pause();
});

test("pause stops advancing", async () => {
  const e = new Reader(1500); e.load(text);
  e.toggle(); e.toggle();
  const index = e.index;
  await new Promise((r) => setTimeout(r, 150));
  assert.ok(!e.playing && e.index === index);
});

test("load and restart reset", () => {
  const e = new Reader(); e.load(text);
  e.seek(5); e.restart(); assert.equal(e.index, 0);
  e.seek(5); e.play(); e.load("x y");
  assert.ok(!e.playing && e.index === 0 && e.tokens.length === 2);
});

test("formatTime", () => {
  assert.equal(formatTime(0), "0:00");
  assert.equal(formatTime(65.4), "1:05");
  assert.equal(formatTime(3600), "60:00");
});

test("slow start multiplier", () => {
  assert.deepEqual([0, 1, 2, 3, 4, 5, 6, 100].map(slowStartMultiplier), [2.0, 1.7, 1.45, 1.25, 1.1, 1, 1, 1]);
});

test("slow start ramp resets on play, not on seek", async () => {
  const e = new Reader(1500); e.load(text);
  e.play();
  for (let n = 0; n < 100 && e.wordsSincePlay < 2; n++) await new Promise((r) => setTimeout(r, 10));
  const shown = e.wordsSincePlay;
  e.seek(0);
  assert.ok(shown >= 2 && e.wordsSincePlay === shown);
  e.pause(); e.play();
  assert.equal(e.wordsSincePlay, 0);
  e.pause();
});

test("textHash is FNV-1a 32-bit", () => {
  assert.equal(textHash(""), "811c9dc5");
  assert.equal(textHash("a"), "e40c292c");
  assert.equal(textHash("foobar"), "bf9cf968");
  assert.notEqual(textHash("Çığ"), textHash("Cig"));
});
