// 엑셀 드래그&드롭 + 첨부 강제 주입 + 파일명 줄 삭제
(function() {
  'use strict';

  // 전역 노출 (noteAiParse 후처리에서 접근)
  window._attachmentMap = window._attachmentMap || {};

  function init() {
    const ta = document.getElementById('noteRawText');
    if (!ta) {
      console.warn('[excel_drop] noteRawText not found, retry in 500ms');
      setTimeout(init, 500);
      return;
    }
    console.log('[excel_drop] init OK');

    ta.addEventListener('dragover', function(e) {
      e.preventDefault();
      e.stopPropagation();
      ta.style.background = '#fef3c7';
    });

    ta.addEventListener('dragleave', function(e) {
      e.preventDefault();
      ta.style.background = '';
    });

    ta.addEventListener('drop', async function(e) {
      e.preventDefault();
      e.stopPropagation();
      ta.style.background = '';

      const files = (e.dataTransfer && e.dataTransfer.files) || [];
      if (files.length === 0) return;

      const divEl = document.getElementById('noteDivision');
      const divisionId = divEl ? divEl.value : '';
      if (!divisionId) { alert('사업부를 먼저 선택하세요'); return; }

      const status = document.getElementById('noteStatus');

      for (const f of files) {
        const lower = (f.name || '').toLowerCase();
        if (!(lower.endsWith('.xlsx') || lower.endsWith('.xlsm'))) {
          console.log('[excel_drop] skip non-excel:', f.name);
          continue;
        }

        if (status) {
          status.textContent = '📤 엑셀 업로드 중: ' + f.name;
          status.style.color = '#6b7280';
        }

        const fd = new FormData();
        fd.append('file', f);
        fd.append('division_id', divisionId);

        try {
          const r = await fetch('/admin/notes/excel', {
            method: 'POST',
            credentials: 'same-origin',
            body: fd
          });
          if (!r.ok) throw new Error('HTTP ' + r.status);
          const data = await r.json();

          window._attachmentMap[data.filename] = {
            table_ref: data.table_ref,
            table: data.table || null,
            sheet_name: data.sheet_name,
            rows: data.rows,
            cols: data.cols
          };

          // 커서 위치에 파일명 한 줄 삽입
          const start = ta.selectionStart;
          const end = ta.selectionEnd;
          const before = ta.value.substring(0, start);
          const after = ta.value.substring(end);
          const needLeadNL = before.length > 0 && !before.endsWith('\n');
          const insertText = (needLeadNL ? '\n' : '') + '📊 ' + data.filename + '\n';
          ta.value = before + insertText + after;
          const newPos = start + insertText.length;
          ta.selectionStart = ta.selectionEnd = newPos;
          ta.focus();

          if (status) {
            status.textContent = '✅ 엑셀 첨부됨: ' + data.filename + ' (' + data.rows + '행 × ' + data.cols + '열)';
            status.style.color = '#10b981';
          }
          console.log('[excel_drop] uploaded:', data);
        } catch (err) {
          if (status) {
            status.textContent = '❌ 엑셀 업로드 실패: ' + err.message;
            status.style.color = '#dc2626';
          }
          console.error('[excel_drop] upload failed:', err);
        }
      }
    });

    // Backspace/Delete로 📊 파일명 줄 통째 삭제
    ta.addEventListener('keydown', async function(e) {
      if (e.key !== 'Backspace' && e.key !== 'Delete') return;
      const pos = ta.selectionStart;
      if (pos !== ta.selectionEnd) return;

      const val = ta.value;
      let lineStart = val.lastIndexOf('\n', pos - 1) + 1;
      let lineEnd = val.indexOf('\n', pos);
      if (lineEnd < 0) lineEnd = val.length;

      const line = val.substring(lineStart, lineEnd).trim();
      const mm = line.match(/(.+?\.xlsx?)/i);
      if (!mm) return;

      const fname = mm[1].trim();
      const attach = window._attachmentMap[fname];
      if (!attach) return;

      e.preventDefault();

      let newStart = lineStart;
      let newEnd = lineEnd;
      if (newEnd < val.length) newEnd += 1;
      else if (newStart > 0) newStart -= 1;

      ta.value = val.substring(0, newStart) + val.substring(newEnd);
      ta.selectionStart = ta.selectionEnd = newStart;
      delete window._attachmentMap[fname];

      const status = document.getElementById('noteStatus');
      if (status) {
        status.textContent = '🗑️ 첨부 삭제됨: ' + fname;
        status.style.color = '#6b7280';
      }
      console.log('[excel_drop] deleted:', fname);
    });
  }

  // noteAiParse 후처리: AI가 카드 돌려주면 표 강제 주입
  // - 원본 noteAiParse 함수를 감싸서 자동으로 실행
  function wrapNoteAiParse() {
    if (typeof window.noteAiParse !== 'function') {
      setTimeout(wrapNoteAiParse, 500);
      return;
    }
    if (window.noteAiParse.__wrapped) return;

    const orig = window.noteAiParse;
    window.noteAiParse = async function() {
      await orig.apply(this, arguments);

      // 후처리: _noteParsedCards에 표 강제 주입
      if (!window._noteParsedCards || !Array.isArray(window._noteParsedCards)) return;
      if (Object.keys(window._attachmentMap).length === 0) return;

      const cards = window._noteParsedCards;
      const usedRefs = new Set();

      for (const card of cards) {
        for (const sec of (card.sections || [])) {
          for (let i = 0; i < (sec.items || []).length; i++) {
            const it = sec.items[i];
            const txt = String((it && it.text) || '').trim();
            const mm = txt.match(/(.+?\.xlsx?)/i);
            if (mm) {
              const fname = mm[1].trim();
              const attach = window._attachmentMap[fname];
              if (attach) {
                sec.items[i] = { type: 'table', text: fname, table_ref: attach.table_ref, table_data: attach.table };
                usedRefs.add(attach.table_ref);
              }
            }
          }
        }
      }

      const unused = Object.entries(window._attachmentMap)
        .filter(function(e) { return !usedRefs.has(e[1].table_ref); });

      if (unused.length > 0 && cards.length > 0) {
        const card0 = cards[0];
        if (!card0.sections || card0.sections.length === 0) {
          card0.sections = [{ title: '첨부', items: [] }];
        }
        const lastSec = card0.sections[card0.sections.length - 1];
        if (!lastSec.items) lastSec.items = [];
        for (const pair of unused) {
          lastSec.items.push({ type: 'table', text: pair[0], table_ref: pair[1].table_ref, table_data: pair[1].table });
        }
      }

      // 미리보기 다시 그리기
      if (typeof window.renderNotePreview === 'function') {
        window.renderNotePreview(cards);
      }
      console.log('[excel_drop] injected tables, total cards:', cards.length);
    };
    window.noteAiParse.__wrapped = true;
    console.log('[excel_drop] noteAiParse wrapped');
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function() {
      init();
      wrapNoteAiParse();
    });
  } else {
    init();
    wrapNoteAiParse();
  }
})();
