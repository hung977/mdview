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

  function headingText(inline) {
    return inline.children
      ? inline.children.filter(t => t.type === 'text' || t.type === 'code_inline').map(t => t.content).join('')
      : inline.content;
  }
  function uniqueSlug(text, slugs) {
    let slug = slugify(text);
    const seen = slugs[slug] || 0;
    slugs[slug] = seen + 1;
    return seen ? slug + '-' + seen : slug;
  }

  // Heading ids (same algorithm as outline() below, so sidebar ids match rendered ids).
  const defaultHeadingOpen = md.renderer.rules.heading_open ||
    ((tokens, idx, options, env, self) => self.renderToken(tokens, idx, options));
  md.renderer.rules.heading_open = function (tokens, idx, options, env, self) {
    tokens[idx].attrSet('id', uniqueSlug(headingText(tokens[idx + 1]), env.slugs));
    return defaultHeadingOpen(tokens, idx, options, env, self);
  };

  // Table of contents for the sidebar: [{id, level, text, line}].
  function outline(source) {
    const slugs = {};
    const result = [];
    const tokens = md.parse(source, {});
    for (let i = 0; i < tokens.length; i++) {
      if (tokens[i].type !== 'heading_open') continue;
      const text = headingText(tokens[i + 1]);
      result.push({ id: uniqueSlug(text, slugs), level: Number(tokens[i].tag.slice(1)), text,
                    line: tokens[i].map ? tokens[i].map[0] : -1 });
    }
    return result;
  }

  // Raw view: escape the source, wrapping heading lines in anchors so the sidebar still works.
  function rawHtml(source, headings) {
    const lines = source.split('\n').map(md.utils.escapeHtml);
    for (const h of headings) {
      if (h.line >= 0 && h.line < lines.length) lines[h.line] = '<span id="' + h.id + '">' + lines[h.line] + '</span>';
    }
    return '<pre class="raw-source"><code>' + lines.join('\n') + '</code></pre>';
  }

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
  let mode = 'preview';   // 'preview' | 'raw'
  const content = document.getElementById('content');

  // Document statistics for the Info inspector, counted on the rendered HTML.
  function stats(source, html) {
    const probe = document.createElement('template');
    probe.innerHTML = html;
    const count = sel => probe.content.querySelectorAll(sel).length;
    return {
      words: (source.match(/\S+/g) || []).length,
      characters: source.length,
      lines: source.split('\n').length,
      links: count('a[href]'),
      images: count('img'),
      tables: count('table'),
      codeBlocks: count('pre:not(.mermaid)'),
      diagrams: count('pre.mermaid'),
    };
  }

  // Returns {outline, stats} as JSON so Swift can fill the sidebar and the Info inspector.
  window.render = function (source, base) {
    lastSource = source;
    if (base !== undefined) document.querySelector('base').href = base;   // relative images/links
    const headings = outline(source);
    const html = md.render(source, { slugs: {} });
    content.classList.toggle('raw', mode === 'raw');
    content.innerHTML = mode === 'raw' ? rawHtml(source, headings) : html;
    renderDiagrams();
    refreshFind();
    return JSON.stringify({ outline: headings, stats: stats(source, html) });
  };

  // Height of the window chrome (toolbar, find bar) the page scrolls underneath.
  window.setTopInset = function (px) {
    document.documentElement.style.setProperty('--top-inset', px + 'px');
  };

  window.scrollToHeading = function (id) {
    const target = document.getElementById(id);
    if (target) target.scrollIntoView({ block: 'start' });
    return !!target;
  };

  // Swift toggles between the rendered preview and the raw Markdown source.
  window.setMode = function (newMode) {
    if (newMode === mode) return;
    mode = newMode;
    if (lastSource !== null) render(lastSource);
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

  // ---- Find ----
  // Driven by the native find bar in Swift. Matches are located in #content and painted with the
  // CSS Custom Highlight API, so the page selection is never touched. Each call returns a status
  // string for the bar ("3 of 12", "Not found" or "").
  const highlightsSupported = typeof CSS !== 'undefined' && CSS.highlights && typeof Highlight === 'function';
  // One registered Highlight per role, mutated in place: replacing registry entries leaves stale
  // paint behind in WebKit.
  const matchHighlight = highlightsSupported ? new Highlight() : null;
  const currentHighlight = highlightsSupported ? new Highlight() : null;
  if (highlightsSupported) {
    CSS.highlights.set('find-match', matchHighlight);
    CSS.highlights.set('find-current', currentHighlight);
  }
  let query = '';
  let matches = [];
  let current = -1;

  function collectMatches() {
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
    matchHighlight.clear();
    currentHighlight.clear();
    for (const range of matches) matchHighlight.add(range);
    if (current >= 0) currentHighlight.add(matches[current]);
  }

  function status() {
    if (!query) return '';
    return matches.length ? (current + 1) + ' of ' + matches.length : 'Not found';
  }

  function goTo(index) {
    if (!matches.length) { current = -1; paint(); return status(); }
    current = ((index % matches.length) + matches.length) % matches.length;
    paint();
    const rect = matches[current].getBoundingClientRect();
    if (rect.top < 0 || rect.bottom > innerHeight) {
      scrollTo({ top: scrollY + rect.top - innerHeight / 2, behavior: 'auto' });
    }
    return status();
  }

  window.findSet = function (newQuery) { query = newQuery || ''; collectMatches(); return goTo(0); };
  window.findNext = function () { return goTo(current + 1); };
  window.findPrevious = function () { return goTo(current - 1); };
  window.findClear = function () { query = ''; matches = []; current = -1; paint(); return ''; };
  window.refreshFind = function () { if (query) { collectMatches(); goTo(Math.max(current, 0)); } };
})();
