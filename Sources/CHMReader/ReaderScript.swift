import WebKit

enum ReaderScript {
    static let world = WKContentWorld.world(name: "chmreader")
    static let messageHandler = "chmr"

    /// Runs in an isolated content world in every frame. Highlights are anchored by text position
    /// plus the quoted text and its surrounding context, so they survive small DOM differences.
    static let source = #"""
    (() => {
      if (window.chmReader) return;
      const HL = 'chmr-hl';
      const CONTEXT = 32;
      let styleText = '';

      const post = (msg) => { try { window.webkit.messageHandlers.chmr.postMessage(msg); } catch (e) {} };

      function ensureStyle() {
        const parent = document.head || document.documentElement;
        if (!parent) return;
        let el = document.getElementById('chmr-style');
        if (!el) { el = document.createElement('style'); el.id = 'chmr-style'; }
        if (el.textContent !== styleText) el.textContent = styleText;
        if (el.parentNode !== parent || el !== parent.lastElementChild) parent.appendChild(el);
      }

      function skip(node) {
        const p = node.parentNode;
        if (!p) return true;
        const n = p.nodeName;
        return n === 'SCRIPT' || n === 'STYLE' || n === 'NOSCRIPT' || n === 'TEXTAREA' || n === 'TITLE';
      }

      function buildIndex() {
        const nodes = [];
        const parts = [];
        let pos = 0;
        if (!document.body) return { nodes, text: '' };
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
          acceptNode: (n) => skip(n) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT
        });
        let n;
        while ((n = walker.nextNode())) {
          nodes.push({ node: n, start: pos });
          parts.push(n.nodeValue);
          pos += n.nodeValue.length;
        }
        return { nodes, text: parts.join('') };
      }

      function offsetOf(idx, container, offset) {
        if (container.nodeType === Node.TEXT_NODE) {
          const hit = idx.nodes.find((e) => e.node === container);
          if (hit) return hit.start + offset;
        }
        const r = document.createRange();
        r.setStart(container, offset);
        r.collapse(true);
        for (const e of idx.nodes) {
          if (r.comparePoint(e.node, 0) >= 0) return e.start;
        }
        return idx.text.length;
      }

      function capture() {
        const sel = window.getSelection();
        if (!sel || sel.isCollapsed || sel.rangeCount === 0) return null;
        const range = sel.getRangeAt(0);
        const idx = buildIndex();
        const start = offsetOf(idx, range.startContainer, range.startOffset);
        const end = offsetOf(idx, range.endContainer, range.endOffset);
        if (end <= start) return null;
        const exact = idx.text.slice(start, end);
        if (!exact.trim()) return null;
        return {
          exact, start, end,
          prefix: idx.text.slice(Math.max(0, start - CONTEXT), start),
          suffix: idx.text.slice(end, end + CONTEXT)
        };
      }

      function locate(a, idx) {
        const t = idx.text;
        if (t.slice(a.start, a.end) === a.exact) return [a.start, a.end];
        let best = -1, bestScore = -Infinity;
        for (let i = t.indexOf(a.exact); i !== -1; i = t.indexOf(a.exact, i + 1)) {
          let score = 0;
          if (a.prefix && t.slice(Math.max(0, i - a.prefix.length), i) === a.prefix) score += 2;
          const after = i + a.exact.length;
          if (a.suffix && t.slice(after, after + a.suffix.length) === a.suffix) score += 2;
          score -= Math.abs(i - a.start) / 1e7;
          if (score > bestScore) { bestScore = score; best = i; }
        }
        return best < 0 ? null : [best, best + a.exact.length];
      }

      function wrap(a, s, e, idx) {
        for (const { node, start } of idx.nodes) {
          const end = start + node.nodeValue.length;
          if (end <= s || start >= e) continue;
          const from = Math.max(s, start) - start;
          const to = Math.min(e, end) - start;
          if (to <= from) continue;
          let target = node;
          if (from > 0) target = target.splitText(from);
          if (to - from < target.nodeValue.length) target.splitText(to - from);
          const parentName = target.parentNode && target.parentNode.nodeName;
          if (!target.nodeValue.trim() && /^(TABLE|TBODY|THEAD|TR|UL|OL|DL)$/.test(parentName)) continue;
          const m = document.createElement('mark');
          m.className = HL;
          m.dataset.id = a.id;
          m.dataset.color = a.color;
          m.dataset.note = a.note ? '1' : '0';
          target.parentNode.insertBefore(m, target);
          m.appendChild(target);
        }
      }

      function marks(id) {
        return document.querySelectorAll('mark.' + HL + '[data-id="' + CSS.escape(id) + '"]');
      }

      function remove(id) {
        marks(id).forEach((m) => {
          const p = m.parentNode;
          while (m.firstChild) p.insertBefore(m.firstChild, m);
          p.removeChild(m);
          p.normalize();
        });
      }

      function apply(a) {
        remove(a.id);
        const idx = buildIndex();
        const r = locate(a, idx);
        if (!r) return false;
        wrap(a, r[0], r[1], idx);
        return true;
      }

      document.addEventListener('click', (e) => {
        const m = e.target && e.target.closest && e.target.closest('mark.' + HL);
        const sel = window.getSelection();
        if (m && (!sel || sel.isCollapsed)) {
          e.preventDefault();
          e.stopPropagation();
          post({ type: 'highlightClicked', id: m.dataset.id });
        }
      }, true);

      let hadSelection = false;
      document.addEventListener('selectionchange', () => {
        const sel = window.getSelection();
        const has = !!sel && !sel.isCollapsed && sel.toString().trim().length > 0;
        if (has !== hadSelection) { hadSelection = has; post({ type: 'selection', has }); }
      });

      document.addEventListener('DOMContentLoaded', () => {
        ensureStyle();
        if (!document.documentElement.lang) document.documentElement.lang = 'zh-Hant';
      });

      window.chmReader = {
        setStyle(css) { styleText = css; ensureStyle(); },
        capture,
        apply,
        restore(items) { let n = 0; for (const a of items) if (apply(a)) n++; return n; },
        remove,
        update(id, color, hasNote) {
          marks(id).forEach((m) => { m.dataset.color = color; m.dataset.note = hasNote ? '1' : '0'; });
        },
        scrollTo(id) {
          const all = marks(id);
          if (!all.length) return false;
          all[0].scrollIntoView({ block: 'center', behavior: 'smooth' });
          all.forEach((m) => m.classList.add('chmr-flash'));
          setTimeout(() => all.forEach((m) => m.classList.remove('chmr-flash')), 1500);
          return true;
        },
        clearSelection() { const s = window.getSelection(); if (s) s.removeAllRanges(); }
      };
    })();
    """#
}
