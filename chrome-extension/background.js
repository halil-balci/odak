// Right-click "Read with Odak" reads the selection; the toolbar icon reads the selection or,
// without one, the page's main text. Everything stays in the browser.

chrome.runtime.onInstalled.addListener(() => {
  // onInstalled also fires on updates, when the saved menu item still exists.
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: "odak-read",
      title: chrome.i18n.getMessage("menuTitle"),
      contexts: ["selection"],
    });
  });
});

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId !== "odak-read") return;
  // info.selectionText turns line breaks into spaces, which loses the paragraph pauses, so prefer the page's
  // own selection. Scripting fails in the PDF viewer and on chrome:// pages -> fallback.
  const text = (await runInTab(tab?.id, info.frameId, () => getSelection().toString())) || info.selectionText;
  openReader(text ? { text } : { error: "errorNoText" });
});

chrome.action.onClicked.addListener(async (tab) => {
  const text = await runInTab(tab.id, 0, pageText);
  openReader(typeof text !== "string" ? { error: "errorRestricted" } : text.trim() ? { text } : { error: "errorNoText" });
});

/** Runs in the page: the selection, or the main text. innerText keeps paragraph breaks. */
function pageText() {
  const selection = getSelection().toString();
  if (selection.trim()) return selection;
  // shortcut: first of article / main / [role=main] with text, longest match wins; use a readability
  // heuristic if pages with small <article> cards read poorly.
  for (const selector of ["article", "main", "[role=main]"]) {
    const best = [...document.querySelectorAll(selector)]
      .map((el) => el.innerText)
      .reduce((a, b) => (b.trim().length > a.trim().length ? b : a), "");
    if (best.trim()) return best;
  }
  return document.body?.innerText ?? "";
}

/** The function's result, or undefined when the page can't be scripted. */
async function runInTab(tabId, frameId, func) {
  if (tabId === undefined || tabId < 0) return undefined;
  try {
    const [result] = await chrome.scripting.executeScript({ target: { tabId, frameIds: [frameId ?? 0] }, func });
    return result?.result;
  } catch {
    return undefined;
  }
}

/** Hands `{text}` or `{error}` to a new reader window; the reader deletes it after reading. */
async function openReader(payload) {
  const id = crypto.randomUUID();
  await chrome.storage.session.set({ [id]: payload });
  await chrome.windows.create({ url: `reader.html?id=${id}`, type: "popup", width: 760, height: 460 });
}
