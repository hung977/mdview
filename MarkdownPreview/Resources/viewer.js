/* Renders Markdown into #content. Swift calls render(text) after the page loads and on every
   file change; the DOM is replaced in place so the scroll position survives. */
(function () {
  'use strict';

  // GitHub-style heading slugs so tables of contents ([..](#section)) work.
  function slugify(text) {
    return text.toLowerCase().trim()
      .replace(/[^\p{L}\p{N}\p{M}\s-]/gu, '')
      .replace(/\s+/g, '-');
  }

  const md = window.markdownit({
    html: true,
    linkify: true,
    breaks: false,
    highlight(str, lang) {
      if (lang === 'mermaid') {
        return '<pre class="mermaid">' + md.utils.escapeHtml(str) + '</pre>';
      }
      if (lang && window.hljs && hljs.getLanguage(lang)) {
        try {
          return '<pre><code class="hljs language-' + md.utils.escapeHtml(lang) + '">' +
            hljs.highlight(str, { language: lang, ignoreIllegals: true }).value + '</code></pre>';
        } catch (_) { /* fall through */ }
      }
      return '<pre><code class="hljs">' + md.utils.escapeHtml(str) + '</code></pre>';
    }
  });

  // Heading ids.
  const defaultHeadingOpen = md.renderer.rules.heading_open ||
    ((tokens, idx, options, env, self) => self.renderToken(tokens, idx, options));
  md.renderer.rules.heading_open = function (tokens, idx, options, env, self) {
    const inline = tokens[idx + 1];
    const text = inline.children
      ? inline.children.filter(t => t.type === 'text' || t.type === 'code_inline').map(t => t.content).join('')
      : inline.content;
    let slug = slugify(text);
    const seen = env.slugs[slug] || 0;
    env.slugs[slug] = seen + 1;
    if (seen) slug += '-' + seen;
    tokens[idx].attrSet('id', slug);
    return defaultHeadingOpen(tokens, idx, options, env, self);
  };

  // Task lists: "- [ ] item" / "- [x] item".
  md.core.ruler.after('inline', 'task_lists', function (state) {
    const tokens = state.tokens;
    for (let i = 2; i < tokens.length; i++) {
      const inline = tokens[i];
      if (inline.type !== 'inline' || tokens[i - 1].type !== 'paragraph_open' ||
          tokens[i - 2].type !== 'list_item_open') continue;
      const match = /^\[([ xX])\][ \t]+/.exec(inline.content);
      if (!match) continue;
      const first = inline.children[0];
      if (!first || first.type !== 'text') continue;
      first.content = first.content.slice(match[0].length);
      const checkbox = new state.Token('html_inline', '', 0);
      checkbox.content = '<input class="task-list-item-checkbox" type="checkbox" disabled' +
        (match[1] === ' ' ? '' : ' checked') + '> ';
      inline.children.unshift(checkbox);
      tokens[i - 2].attrJoin('class', 'task-list-item');
      for (let j = i - 3; j >= 0; j--) {
        if ((tokens[j].type === 'bullet_list_open' || tokens[j].type === 'ordered_list_open') &&
            tokens[j].level === tokens[i - 2].level - 1) {
          tokens[j].attrJoin('class', 'contains-task-list');
          break;
        }
      }
    }
  });

  let lastSource = null;
  const content = document.getElementById('content');

  window.render = function (source, base) {
    lastSource = source;
    if (base !== undefined) document.querySelector('base').href = base;   // relative images/links
    content.innerHTML = md.render(source, { slugs: {} });
    renderDiagrams();
    if (findVisible()) updateFindCount();
  };

  function renderDiagrams() {
    if (!window.mermaid) return;
    const nodes = content.querySelectorAll('pre.mermaid');
    if (!nodes.length) return;
    const dark = matchMedia('(prefers-color-scheme: dark)').matches;
    mermaid.initialize({ startOnLoad: false, theme: dark ? 'dark' : 'default',
                         securityLevel: 'strict', suppressErrorRendering: true });
    mermaid.run({ nodes }).catch(() => {});
  }
  // Swift injects mermaid lazily, then calls this.
  window.renderDiagrams = renderDiagrams;

  // In-page anchors (table of contents) scroll instead of navigating away from the shell page.
  document.addEventListener('click', e => {
    const anchor = e.target.closest('a');
    const href = anchor && anchor.getAttribute('href');
    if (!href || !href.startsWith('#')) return;
    e.preventDefault();
    let id = href.slice(1);
    try { id = decodeURIComponent(id); } catch (_) { /* keep raw */ }
    const target = document.getElementById(id);
    if (target) target.scrollIntoView();
  });

  matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
    if (lastSource !== null && content.querySelector('pre.mermaid, svg[id^="mermaid"]')) render(lastSource);
  });

  // ---- Find bar (window.find highlights matches through the native selection) ----
  const bar = document.getElementById('findbar');
  const input = document.getElementById('findinput');
  const count = document.getElementById('findcount');

  function findVisible() { return !bar.hidden; }

  function updateFindCount() {
    const q = input.value;
    if (!q) { count.textContent = ''; return; }
    const haystack = content.innerText.toLowerCase();
    let n = 0, pos = 0;
    const needle = q.toLowerCase();
    while ((pos = haystack.indexOf(needle, pos)) !== -1) { n++; pos += needle.length; }
    count.textContent = n === 0 ? 'Not found' : n + (n === 1 ? ' match' : ' matches');
  }

  function find(backwards, fromStart) {
    const q = input.value;
    if (!q) return;
    if (fromStart) getSelection().removeAllRanges();
    window.find(q, false, backwards, true, false, false, false);
  }

  window.showFind = function () {
    bar.hidden = false;
    input.focus();
    input.select();
    updateFindCount();
  };
  window.findNext = function () { if (findVisible()) find(false, false); else showFind(); };
  window.findPrevious = function () { if (findVisible()) find(true, false); else showFind(); };
  window.hideFind = function () { bar.hidden = true; input.blur(); };

  input.addEventListener('input', () => { updateFindCount(); find(false, true); });
  input.addEventListener('keydown', e => {
    if (e.key === 'Enter') { find(e.shiftKey, false); e.preventDefault(); }
    else if (e.key === 'Escape') { hideFind(); e.preventDefault(); }
  });
  document.getElementById('findnext').addEventListener('click', () => find(false, false));
  document.getElementById('findprev').addEventListener('click', () => find(true, false));
  document.getElementById('finddone').addEventListener('click', hideFind);
  document.addEventListener('keydown', e => { if (e.key === 'Escape' && findVisible()) hideFind(); });
})();
