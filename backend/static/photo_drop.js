// 사진 드래그&드롭 + 원본텍스트 아래 썸네일 프리뷰 + X/Backspace 2번 삭제 + AI 후처리
(function() {
  'use strict';

  window._photoMap = window._photoMap || {};

  var PREVIEW_ID = 'notePhotoInlinePreview';
  var lastBackspace = { fname: '', ts: 0 };

  function nl() {
    return String.fromCharCode(10);
  }

  function isPhotoFileName(name) {
    return /\.(jpg|jpeg|png|gif|webp)$/i.test(String(name || ''));
  }

  function extractPhotoFileNameFromLine(line) {
    var s = String(line || '').trim();
    var m = s.match(/([^\s\/\\]+\.(?:jpg|jpeg|png|gif|webp))/i);
    return m ? m[1].trim() : '';
  }

  function getTextarea() {
    return document.getElementById('noteRawText');
  }

  function getStatus() {
    return document.getElementById('noteStatus');
  }

  function ensurePreviewBox() {
    var ta = getTextarea();
    if (!ta) return null;

    var box = document.getElementById(PREVIEW_ID);
    if (box) return box;

    box = document.createElement('div');
    box.id = PREVIEW_ID;
    box.style.cssText = [
      'display:none',
      'margin-top:10px',
      'padding:10px 12px',
      'border:1px solid #e5e7eb',
      'border-radius:8px',
      'background:#fafafa'
    ].join(';');

    ta.insertAdjacentElement('afterend', box);
    return box;
  }

  function getPhotoMarkersFromTextarea() {
    var ta = getTextarea();
    if (!ta) return [];
    var lines = String(ta.value || '').split(/\r?\n/);
    var out = [];
    lines.forEach(function(line) {
      var fname = extractPhotoFileNameFromLine(line);
      if (fname && isPhotoFileName(fname)) {
        out.push(fname);
      }
    });
    return out;
  }

  function removePhotoMarkerLine(filename) {
    var ta = getTextarea();
    if (!ta) return;
    var lines = String(ta.value || '').split(/\r?\n/);
    var next = [];
    lines.forEach(function(line) {
      var fname = extractPhotoFileNameFromLine(line);
      if (fname && fname === filename) return;
      next.push(line);
    });
    ta.value = next.join(nl());
  }

  function removePhotoAttachment(filename, reason) {
    if (!filename) return;
    removePhotoMarkerLine(filename);
    delete window._photoMap[filename];
    syncPhotoPreviewFromTextarea();

    var status = getStatus();
    if (status) {
      status.textContent = '🗑️ 사진 첨부 삭제: ' + filename;
      status.style.color = '#6b7280';
    }
    console.log('[photo_drop] removed:', filename, reason || '');
  }

  function renderPreviewCard(filename, meta) {
    var url = (meta && meta.url) ? meta.url : '';
    if (!url) return '';

    return `
      <div data-fname="${filename}"
           style="display:flex;align-items:center;gap:10px;padding:8px 10px;background:#fff;border:1px solid #e5e7eb;border-radius:8px;">
        <img src="${url}"
             style="width:64px;height:64px;object-fit:cover;border-radius:6px;border:1px solid #d1d5db;flex-shrink:0;" />
        <div style="min-width:0;flex:1;">
          <div style="font-size:12px;color:#111827;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${filename}</div>
          <div style="font-size:11px;color:#6b7280;margin-top:2px;">원본 텍스트와 연결된 사진 첨부</div>
        </div>
        <button type="button"
                data-remove-photo="${filename}"
                style="width:28px;height:28px;border:1px solid #fca5a5;border-radius:6px;background:#fff1f2;color:#dc2626;cursor:pointer;font-size:14px;line-height:1;">
          ×
        </button>
      </div>
    `;
  }

  function syncPhotoPreviewFromTextarea() {
    var box = ensurePreviewBox();
    if (!box) return;

    var markers = getPhotoMarkersFromTextarea();
    var alive = {};

    // textarea에서 @@photo_ref= 마커도 직접 읽어 _photoMap 복원
    var ta = getTextarea();
    if (ta) {
      var rawText = String(ta.value || '');
      var lineRe = /\u{1F4F7}\s*([^\n\r@]+?)\s*@@photo_ref=([^\s\n\r]+)/gu;
      var m;
      while ((m = lineRe.exec(rawText)) !== null) {
        var fn = m[1].trim();
        var ref = m[2].trim();
        if (fn && ref) {
          if (!window._photoMap[fn]) {
            window._photoMap[fn] = { photo_ref: ref, url: '/note_photos/' + ref };
          }
        }
      }
    }

    markers.forEach(function(fname) {
      if (window._photoMap[fname]) {
        alive[fname] = window._photoMap[fname];
      }
    });

    Object.keys(window._photoMap).forEach(function(fname) {
      if (!alive[fname]) {
        delete window._photoMap[fname];
      }
    });

    var names = Object.keys(alive);
    if (names.length === 0) {
      box.style.display = 'none';
      box.innerHTML = '';
      return;
    }

    var html = `
      <div style="font-size:12px;color:#374151;font-weight:600;margin-bottom:8px;">사진 첨부 미리보기</div>
      <div style="display:flex;flex-direction:column;gap:8px;">
        ${names.map(function(fname) { return renderPreviewCard(fname, alive[fname]); }).join('')}
      </div>
    `;
    box.innerHTML = html;
    box.style.display = 'block';

    box.querySelectorAll('[data-remove-photo]').forEach(function(btn) {
      btn.addEventListener('click', function() {
        var fname = btn.getAttribute('data-remove-photo') || '';
        removePhotoAttachment(fname, 'button');
      });
    });
  }

  function handlePhotoBackspace(e) {
    if (e.key !== 'Backspace') return;

    var ta = getTextarea();
    if (!ta) return;
    if (ta.selectionStart !== ta.selectionEnd) return;

    var value = String(ta.value || '');
    var pos = ta.selectionStart;
    var lines = value.split(/\r?\n/);

    var acc = 0;
    var currentLine = '';
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      var start = acc;
      var end = acc + line.length;
      if (pos >= start && pos <= end) {
        currentLine = line;
        break;
      }
      acc = end + 1;
    }

    var fname = extractPhotoFileNameFromLine(currentLine);
    if (!fname || !window._photoMap[fname]) return;

    e.preventDefault();

    var now = Date.now();
    if (lastBackspace.fname === fname && (now - lastBackspace.ts) <= 1200) {
      lastBackspace = { fname: '', ts: 0 };
      removePhotoAttachment(fname, 'double-backspace');
      return;
    }

    lastBackspace = { fname: fname, ts: now };
    var status = getStatus();
    if (status) {
      status.textContent = '한 번 더 Backspace 하면 사진 첨부가 삭제됩니다: ' + fname;
      status.style.color = '#92400e';
    }
  }

  async function uploadDroppedPhotos(files) {
    var ta = getTextarea();
    if (!ta) return;

    var divEl = document.getElementById('noteDivision');
    var divisionId = divEl ? divEl.value : '';
    if (!divisionId) {
      alert('사업부를 먼저 선택하세요');
      return;
    }

    var status = getStatus();
    var exts = ['.jpg', '.jpeg', '.png', '.gif', '.webp'];

    for (const f of files) {
      var lower = String(f.name || '').toLowerCase();
      var isPhoto = exts.some(function(ext) { return lower.endsWith(ext); });
      if (!isPhoto) continue;

      if (status) {
        status.textContent = '📤 사진 업로드 중: ' + f.name;
        status.style.color = '#6b7280';
      }

      var fd = new FormData();
      fd.append('file', f);
      fd.append('division_id', divisionId);

      try {
        const r = await fetch('/admin/notes/photo', {
          method: 'POST',
          credentials: 'same-origin',
          body: fd
        });
        if (!r.ok) throw new Error('HTTP ' + r.status);
        const data = await r.json();

        window._photoMap[f.name] = {
          photo_ref: data.photo_ref,
          url: data.url
        };

        var start = ta.selectionStart;
        var end = ta.selectionEnd;
        var before = ta.value.substring(0, start);
        var after = ta.value.substring(end);
        var needLeadNL = before.length > 0 && !before.endsWith(nl());
        var insertText = (needLeadNL ? nl() : '') + '📷 ' + f.name + ' @@photo_ref=' + data.photo_ref + nl();

        ta.value = before + insertText + after;
        var newPos = start + insertText.length;
        ta.setSelectionRange(newPos, newPos);

        syncPhotoPreviewFromTextarea();

        if (status) {
          status.textContent = '✅ 사진 첨부: ' + f.name;
          status.style.color = '#10b981';
        }
        console.log('[photo_drop] uploaded:', f.name, data.photo_ref);
      } catch (err) {
        if (status) {
          status.textContent = '❌ 사진 업로드 실패: ' + err.message;
          status.style.color = '#dc2626';
        }
        console.error('[photo_drop] upload failed:', err);
      }
    }
  }

  function init() {
    var ta = getTextarea();
    if (!ta) {
      setTimeout(init, 500);
      return;
    }

    ensurePreviewBox();
    syncPhotoPreviewFromTextarea();

    console.log('[photo_drop] init OK');

    ta.addEventListener('drop', async function(e) {
      var files = (e.dataTransfer && e.dataTransfer.files) || [];
      if (!files.length) return;
      await uploadDroppedPhotos(files);
    });

    ta.addEventListener('input', function() {
      syncPhotoPreviewFromTextarea();
    });

    ta.addEventListener('keydown', function(e) {
      handlePhotoBackspace(e);
    });
  }

  function wrapNoteAiParseForPhoto() {
    if (typeof window.noteAiParse !== 'function') {
      setTimeout(wrapNoteAiParseForPhoto, 500);
      return;
    }
    if (window.noteAiParse.__photo_wrapped) return;

    var prev = window.noteAiParse;
    window.noteAiParse = async function() {
      await prev.apply(this, arguments);

      var cards = window._noteParsedCards;
      if (!cards || !Array.isArray(cards)) return;
      if (Object.keys(window._photoMap).length === 0) return;

      var photoExtRe = /([^\s\/\\]+\.(?:jpg|jpeg|png|gif|webp))/i;
      var usedRefs = new Set();

      cards.forEach(function(card) {
        (card.sections || []).forEach(function(sec) {
          for (var i = 0; i < (sec.items || []).length; i++) {
            var it = sec.items[i];
            var txt = String((it && it.text) || '').trim();
            var refMatch = txt.match(/@@photo_ref=([^\s]+)/i);
            if (refMatch) {
              var photoRef = refMatch[1].trim();
              var fnameMatch = txt.match(photoExtRe);
              var cleanText = (fnameMatch ? fnameMatch[1].trim() : '') ||
                              txt.replace(/\s*@@photo_ref=[^\s]+/i, '').trim();
              sec.items[i] = {
                type: 'photo',
                text: cleanText,
                photo_ref: photoRef
              };
              usedRefs.add(photoRef);
              continue;
            }
            var mm = txt.match(photoExtRe);
            if (mm) {
              var fname = mm[1].trim();
              var attach = window._photoMap[fname];
              if (attach) {
                sec.items[i] = {
                  type: 'photo',
                  text: fname,
                  photo_ref: attach.photo_ref
                };
                usedRefs.add(attach.photo_ref);
              }
            }
          }
        });
      });

      var unused = Object.entries(window._photoMap)
        .filter(function(pair) { return !usedRefs.has(pair[1].photo_ref); });

      if (unused.length > 0 && cards.length > 0) {
        var card0 = cards[0];
        if (!card0.sections || card0.sections.length === 0) {
          card0.sections = [{ title: '첨부', items: [] }];
        }
        var lastSec = card0.sections[card0.sections.length - 1];
        if (!lastSec.items) lastSec.items = [];

        unused.forEach(function(pair) {
          lastSec.items.push({
            type: 'photo',
            text: pair[0],
            photo_ref: pair[1].photo_ref
          });
        });
      }

      if (typeof window.renderNotePreview === 'function') {
        window.renderNotePreview(cards);
      }
      console.log('[photo_drop] injected photos');
    };

    window.noteAiParse.__photo_wrapped = true;
    console.log('[photo_drop] noteAiParse wrapped (photo)');
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function() {
      init();
      wrapNoteAiParseForPhoto();
    });
  } else {
    init();
    wrapNoteAiParseForPhoto();
  }
})();
