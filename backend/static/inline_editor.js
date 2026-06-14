/* inline_editor.js — contenteditable 어댑터
 * 목적:
 *   - #noteRawText 가 div[contenteditable] 일 때
 *   - 기존 .value 기반 코드가 한 줄도 안 고쳐도 동작하도록 어댑터 부여
 *   - <img data-photo-fname="..."> 는 .value 읽을 때 "📷 파일명" 마커로 변환
 *   - .value = "..." 쓰면 마커를 다시 <img>로 복원 (단, _photoMap 에 등록된 경우)
 *   - insertAtCaret(html|node) 헬퍼 노출
 *   - placeholder 시뮬레이션
 */
(function() {
  'use strict';

  const TARGET_ID = 'noteRawText';

  function getEl() {
    return document.getElementById(TARGET_ID);
  }

  // contenteditable DOM → 텍스트 (이미지를 "📷 파일명" 마커로)
  function domToText(root) {
    if (!root) return '';
    const lines = [];
    let buf = '';

    function flushBuf() {
      lines.push(buf);
      buf = '';
    }

    function walk(node) {
      if (node.nodeType === Node.TEXT_NODE) {
        buf += node.nodeValue || '';
        return;
      }
      if (node.nodeType !== Node.ELEMENT_NODE) return;

      const tag = node.tagName;

      if (tag === 'IMG') {
        const fname = node.getAttribute('data-photo-fname') || '';
        if (fname) buf += '📷 ' + fname;
        return;
      }
      if (tag === 'BR') {
        flushBuf();
        return;
      }
      if (tag === 'DIV' || tag === 'P') {
        Array.from(node.childNodes).forEach(walk);
        flushBuf();
        return;
      }
      Array.from(node.childNodes).forEach(walk);
    }

    Array.from(root.childNodes).forEach(walk);
    if (buf !== '') flushBuf();

    return lines.join('\n');
  }

  function buildPhotoImg(fname, url) {
    const img = document.createElement('img');
    img.src = url;
    img.alt = fname;
    img.setAttribute('data-photo-fname', fname);
    img.style.cssText = [
      'display:inline-block',
      'max-width:200px',
      'max-height:140px',
      'margin:4px 6px',
      'vertical-align:middle',
      'border:1px solid #d1d5db',
      'border-radius:6px',
      'cursor:pointer'
    ].join(';');
    img.contentEditable = 'false';
    return img;
  }

  // 텍스트 → contenteditable DOM (📷 마커를 <img>로 복원)
  function textToDom(root, text) {
    if (!root) return;
    root.innerHTML = '';

    const lines = String(text == null ? '' : text).split(/\r?\n/);
    const photoLineRe = /📷\s*([^\s\/\\][^\n\r]*\.(?:jpg|jpeg|png|gif|webp))/i;

    lines.forEach((line) => {
      const div = document.createElement('div');
      const m = line.match(photoLineRe);
      if (m) {
        const fname = m[1].trim();
        const meta = (window._photoMap || {})[fname];
        if (meta && meta.url) {
          const prefix = line.substring(0, m.index);
          const suffix = line.substring(m.index + m[0].length);
          if (prefix) div.appendChild(document.createTextNode(prefix));
          div.appendChild(buildPhotoImg(fname, meta.url));
          if (suffix) div.appendChild(document.createTextNode(suffix));
        } else {
          div.appendChild(document.createTextNode(line));
        }
      } else {
        if (line === '') {
          div.appendChild(document.createElement('br'));
        } else {
          div.appendChild(document.createTextNode(line));
        }
      }
      root.appendChild(div);
    });
  }

  // 캐럿 위치에 노드/HTML 삽입
  function insertAtCaret(content) {
    const el = getEl();
    if (!el) return;

    el.focus();
    const sel = window.getSelection();
    let range;

    if (sel && sel.rangeCount > 0 && el.contains(sel.anchorNode)) {
      range = sel.getRangeAt(0);
    } else {
      range = document.createRange();
      range.selectNodeContents(el);
      range.collapse(false);
    }
    range.deleteContents();

    let nodeToInsert;
    if (typeof content === 'string') {
      const tmp = document.createElement('div');
      tmp.innerHTML = content;
      nodeToInsert = document.createDocumentFragment();
      while (tmp.firstChild) nodeToInsert.appendChild(tmp.firstChild);
    } else if (content instanceof Node) {
      nodeToInsert = content;
    } else {
      return;
    }

    let lastNode = null;
    if (nodeToInsert.nodeType === Node.DOCUMENT_FRAGMENT_NODE) {
      lastNode = nodeToInsert.lastChild;
    } else {
      lastNode = nodeToInsert;
    }

    range.insertNode(nodeToInsert);

    if (lastNode) {
      const newRange = document.createRange();
      newRange.setStartAfter(lastNode);
      newRange.collapse(true);
      sel.removeAllRanges();
      sel.addRange(newRange);
    }

    el.dispatchEvent(new Event('input', { bubbles: true }));
  }

  function ensurePlaceholderStyle() {
    if (document.getElementById('inline-editor-style')) return;
    const s = document.createElement('style');
    s.id = 'inline-editor-style';
    s.textContent = [
      '#noteRawText.is-empty:before {',
      '  content: attr(data-placeholder);',
      '  color: #9ca3af;',
      '  white-space: pre-wrap;',
      '  pointer-events: none;',
      '  display: block;',
      '}'
    ].join('\n');
    document.head.appendChild(s);
  }

  function updatePlaceholderVisibility(el) {
    const txt = domToText(el).trim();
    if (txt === '') el.classList.add('is-empty');
    else el.classList.remove('is-empty');
  }

  function installAdapter() {
    const el = getEl();
    if (!el) {
      setTimeout(installAdapter, 200);
      return;
    }
    if (el.__inline_editor_installed) return;
    el.__inline_editor_installed = true;

    try {
      Object.defineProperty(el, 'value', {
        configurable: true,
        get: function() {
          return domToText(this);
        },
        set: function(v) {
          textToDom(this, v);
          updatePlaceholderVisibility(this);
          this.dispatchEvent(new Event('input', { bubbles: true }));
        }
      });
    } catch (e) {
      console.error('[inline_editor] defineProperty failed', e);
    }

    Object.defineProperty(el, 'selectionStart', {
      configurable: true,
      get: function() { return 0; }
    });
    Object.defineProperty(el, 'selectionEnd', {
      configurable: true,
      get: function() { return (this.value || '').length; }
    });
    el.setSelectionRange = function() { /* no-op */ };

    const ph = el.getAttribute('data-placeholder') || el.getAttribute('placeholder') || '';
    if (ph) {
      el.setAttribute('data-placeholder', ph);
      ensurePlaceholderStyle();
      updatePlaceholderVisibility(el);
      el.addEventListener('input', function() { updatePlaceholderVisibility(el); });
      el.addEventListener('blur', function() { updatePlaceholderVisibility(el); });
      el.addEventListener('focus', function() { updatePlaceholderVisibility(el); });
    }

    el.insertAtCaret = insertAtCaret;
    window._inlineEditor = {
      el: el,
      insertAtCaret: insertAtCaret,
      buildPhotoImg: buildPhotoImg,
      domToText: function() { return domToText(el); },
      textToDom: function(t) { textToDom(el, t); },
      isEditor: function(node) { return el.contains(node); }
    };

    console.log('[inline_editor] adapter installed');
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', installAdapter);
  } else {
    installAdapter();
  }
})();