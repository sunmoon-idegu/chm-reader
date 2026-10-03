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
      const STICKY = 'chmr-sticky';
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

      /// DOM range covering text offsets [s, e) of the index.
      function rangeFor(idx, s, e) {
        let startNode = null, startOff = 0, endNode = null, endOff = 0;
        for (const { node, start } of idx.nodes) {
          const end = start + node.nodeValue.length;
          if (!startNode && s >= start && s < end) { startNode = node; startOff = s - start; }
          if (e > start && e <= end) { endNode = node; endOff = e - start; break; }
        }
        if (!startNode || !endNode) return null;
        const r = document.createRange();
        r.setStart(startNode, startOff);
        r.setEnd(endNode, endOff);
        return r;
      }

      /// Selects the nth (0-based) case-insensitive match of q and scrolls it into view.
      function find(q, n) {
        const idx = buildIndex();
        const hay = idx.text.toLowerCase(), needle = q.toLowerCase();
        let pos = -1;
        for (let i = 0, from = 0; i <= n; i++) {
          const p = hay.indexOf(needle, from);
          if (p < 0) break;
          pos = p;
          from = p + needle.length;
        }
        if (pos < 0) return false;
        const r = rangeFor(idx, pos, pos + needle.length);
        if (!r) return false;
        const sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(r);
        const rect = r.getBoundingClientRect();
        window.scrollBy({ top: rect.top - window.innerHeight / 3, behavior: 'smooth' });
        return true;
      }

      function marks(id) {
        const key = '[data-id="' + CSS.escape(id) + '"]';
        return document.querySelectorAll('mark.' + HL + key + ', .' + STICKY + key);
      }

      function remove(id) {
        marks(id).forEach((m) => {
          const p = m.parentNode;
          while (m.firstChild) p.insertBefore(m.firstChild, m);
          p.removeChild(m);
          p.normalize();
        });
      }

      /// Where a sticky note sits: its stored offset if the surrounding text still matches, else where its
      /// context reappears, else the old offset clamped to the page.
      function locatePoint(a, idx) {
        const t = idx.text;
        if (t.slice(Math.max(0, a.start - a.prefix.length), a.start) === a.prefix
            && t.slice(a.start, a.start + a.suffix.length) === a.suffix) return a.start;
        const both = t.indexOf(a.prefix + a.suffix);
        if (a.prefix + a.suffix && both >= 0) return both + a.prefix.length;
        return Math.min(a.start, t.length);
      }

      function applySticky(a) {
        const idx = buildIndex();
        const pos = locatePoint(a, idx);
        const icon = document.createElement('span');
        icon.className = STICKY;
        icon.dataset.id = a.id;
        icon.dataset.color = a.color;
        icon.dataset.note = a.note ? '1' : '0';
        icon.title = '便利貼';
        for (const { node, start } of idx.nodes) {
          const end = start + node.nodeValue.length;
          if (pos < start || pos > end) continue;
          const after = pos - start < node.nodeValue.length ? node.splitText(pos - start) : node.nextSibling;
          node.parentNode.insertBefore(icon, after);
          return true;
        }
        document.body.appendChild(icon);
        return true;
      }

      function apply(a) {
        remove(a.id);
        if (a.kind === 'sticky') return applySticky(a);
        const idx = buildIndex();
        const r = locate(a, idx);
        if (!r) return false;
        wrap(a, r[0], r[1], idx);
        return true;
      }

      let placing = false;
      function setPlacing(on) {
        placing = on;
        document.documentElement.classList.toggle('chmr-placing', on);
      }

      document.addEventListener('click', (e) => {
        if (placing) {
          e.preventDefault();
          e.stopPropagation();
          const caret = document.caretRangeFromPoint(e.clientX, e.clientY);
          const idx = buildIndex();
          const at = caret ? offsetOf(idx, caret.startContainer, caret.startOffset) : 0;
          setPlacing(false);
          post({ type: 'placeSticky', start: at,
                 prefix: idx.text.slice(Math.max(0, at - CONTEXT), at), suffix: idx.text.slice(at, at + CONTEXT) });
          return;
        }
        const m = e.target && e.target.closest && e.target.closest('mark.' + HL + ', .' + STICKY);
        const sel = window.getSelection();
        if (!sel || sel.isCollapsed) {
          if (m) {
            e.preventDefault();
            e.stopPropagation();
            post({ type: 'highlightClicked', id: m.dataset.id });
          } else {
            post({ type: 'pageClicked' });
          }
        }
      }, true);

      // The selection's bounds in the top window, for the floating action bar.
      function selectionRect() {
        const sel = window.getSelection();
        if (!sel || sel.isCollapsed || sel.rangeCount === 0 || !sel.toString().trim()) return null;
        const r = sel.getRangeAt(0).getBoundingClientRect();
        return { x: r.left, y: r.top, w: r.width, h: r.height };
      }

      let barShown = false;
      const isTop = window === window.top;
      document.addEventListener('mouseup', () => {
        if (!isTop || placing) return;
        setTimeout(() => {
          const rect = selectionRect();
          barShown = !!rect;
          if (rect) post({ type: 'selectionEnded', rect });
        }, 0);
      }, true);

      let scrollQueued = false;
      window.addEventListener('scroll', () => {
        if (!barShown || scrollQueued) return;
        scrollQueued = true;
        requestAnimationFrame(() => {
          scrollQueued = false;
          const rect = selectionRect();
          if (rect) post({ type: 'selectionMoved', rect });
        });
      }, true);

      document.addEventListener('keydown', (e) => {
        if (placing && e.key === 'Escape') { setPlacing(false); post({ type: 'placingCancelled' }); }
      }, true);

      let hadSelection = false;
      document.addEventListener('selectionchange', () => {
        const sel = window.getSelection();
        const has = !!sel && !sel.isCollapsed && sel.toString().trim().length > 0;
        if (!has) barShown = false;
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
        clearSelection() { const s = window.getSelection(); if (s) s.removeAllRanges(); },
        setPlacing,
        find
      };
    })();
    """#
}
