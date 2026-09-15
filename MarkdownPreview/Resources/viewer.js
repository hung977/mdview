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
    refreshFind();
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

  // ---- Find bar ----
  // Matches are located in #content and painted with the CSS Custom Highlight API, so the
  // search field keeps focus and the page selection is never touched.
  const bar = document.getElementById('findbar');
  const input = document.getElementById('findinput');
  const count = document.getElementById('findcount');
  const highlightsSupported = typeof CSS !== 'undefined' && CSS.highlights && typeof Highlight === 'function';
  let matches = [];
  let current = -1;

  function findVisible() { return !bar.hidden; }

  function collectMatches(query) {
    matches = [];
    if (!query) return;
    const needle = query.toLowerCase();
    const walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walker.nextNode())) {
      const text = node.data.toLowerCase();
      if (text.length !== node.data.length) continue;   // case mapping changed length; skip rather than mis-offset
      let index = 0;
      while ((index = text.indexOf(needle, index)) !== -1) {
        const range = new Range();
        range.setStart(node, index);
        range.setEnd(node, index + needle.length);
        matches.push(range);
        index += needle.length;
      }
    }
  }

  function paint() {
    if (!highlightsSupported) return;
    CSS.highlights.set('find-match', new Highlight(...matches));
    if (current >= 0) CSS.highlights.set('find-current', new Highlight(matches[current]));
    else CSS.highlights.delete('find-current');
  }

  function clearMatches() {
    matches = [];
    current = -1;
    if (highlightsSupported) { CSS.highlights.delete('find-match'); CSS.highlights.delete('find-current'); }
    count.textContent = '';
  }

  function goTo(index) {
    if (!matches.length) { count.textContent = input.value ? 'Not found' : ''; current = -1; paint(); return; }
    current = ((index % matches.length) + matches.length) % matches.length;
    paint();
    count.textContent = (current + 1) + ' of ' + matches.length;
    const rect = matches[current].getBoundingClientRect();
    const barHeight = bar.getBoundingClientRect().height;
    if (rect.top < barHeight || rect.bottom > innerHeight) {
      scrollTo({ top: scrollY + rect.top - innerHeight / 2, behavior: 'auto' });
    }
  }

  function search() {
    collectMatches(input.value);
    goTo(0);
  }

  window.showFind = function () {
    bar.hidden = false;
    input.focus();
    input.select();
    if (input.value) search();
  };
  window.findNext = function () { if (findVisible() && matches.length) goTo(current + 1); else showFind(); };
  window.findPrevious = function () { if (findVisible() && matches.length) goTo(current - 1); else showFind(); };
  window.hideFind = function () { bar.hidden = true; clearMatches(); input.blur(); };
  window.refreshFind = function () { if (findVisible()) search(); else clearMatches(); };

  input.addEventListener('input', search);
  input.addEventListener('keydown', e => {
    if (e.key === 'Enter') { e.shiftKey ? findPrevious() : findNext(); e.preventDefault(); }
    else if (e.key === 'Escape') { hideFind(); e.preventDefault(); }
  });
  document.getElementById('findnext').addEventListener('click', findNext);
  document.getElementById('findprev').addEventListener('click', findPrevious);
  document.getElementById('finddone').addEventListener('click', hideFind);
  document.addEventListener('keydown', e => { if (e.key === 'Escape' && findVisible()) hideFind(); });
})();
