/* note_loader.js — 기존 노트 카드 단위 불러오기 (프로젝트 칩 모달)
 * - main.py 의 _ADMIN_UPLOAD_HTML 와 완전히 분리됨
 * - 의존: #noteDivision (select), #noteRawText (textarea), #noteReportDate, #noteStatus
 * - 노출: window.openNoteLoadModal()  ← 버튼 클릭 시 호출
 */
(function () {
  'use strict';

  var MODAL_ID = 'noteLoadCardModal';

  // 카드 1개 → 텍스트 (간단 변환: title + sections + items)
  function cardToText(card) {
    var lines = [];
    var title = (card && card.title) ? String(card.title) : '';
    if (title) lines.push('<' + title + '>');
    var sections = (card && card.sections) || [];
    sections.forEach(function (sec) {
      if (sec && sec.title) {
        lines.push('');
        lines.push('[' + sec.title + ']');
      }
      var items = (sec && sec.items) || [];
      items.forEach(function (it) {
        if (!it || !it.text) return;
        var prefix = '';
        if (it.type === 'highlight') prefix = '★ ';
        else if (it.type === 'group_note') prefix = '  ※ ';
        else prefix = '- ';
        var line = prefix + it.text;
        if (it.due_date) line += '  (' + it.due_date + ')';
        lines.push(line);
      });
    });
    return lines.join(String.fromCharCode(10));
  }

  function ensureModal() {
    var existing = document.getElementById(MODAL_ID);
    if (existing) return existing;

    var overlay = document.createElement('div');
    overlay.id = MODAL_ID;
    overlay.style.cssText = [
      'position:fixed', 'inset:0', 'background:rgba(0,0,0,0.45)',
      'display:none', 'align-items:center', 'justify-content:center',
      'z-index:9999'
    ].join(';');

    var box = document.createElement('div');
    box.style.cssText = [
      'background:#fff', 'border-radius:10px', 'padding:20px 22px',
      'min-width:480px', 'max-width:720px', 'max-height:80vh',
      'overflow:auto', 'box-shadow:0 10px 40px rgba(0,0,0,0.25)'
    ].join(';');

    var header = document.createElement('div');
    header.style.cssText = 'display:flex;justify-content:space-between;align-items:center;margin-bottom:14px;';
    var h = document.createElement('h3');
    h.textContent = '📥 기존 노트 불러오기';
    h.style.cssText = 'margin:0;font-size:17px;color:#111827;';
    var closeBtn = document.createElement('button');
    closeBtn.type = 'button';
    closeBtn.textContent = '✕';
    closeBtn.style.cssText = 'background:transparent;border:none;font-size:20px;cursor:pointer;color:#6b7280;padding:4px 8px;';
    closeBtn.addEventListener('click', function () { overlay.style.display = 'none'; });
    header.appendChild(h);
    header.appendChild(closeBtn);

    var info = document.createElement('div');
    info.id = MODAL_ID + '_info';
    info.style.cssText = 'font-size:13px;color:#6b7280;margin-bottom:12px;';

    var chipArea = document.createElement('div');
    chipArea.id = MODAL_ID + '_chips';
    chipArea.style.cssText = 'display:flex;flex-wrap:wrap;gap:8px;';

    var footer = document.createElement('div');
    footer.style.cssText = 'margin-top:16px;font-size:12px;color:#9ca3af;';
    footer.textContent = '칩을 클릭하면 해당 프로젝트의 원본 텍스트가 입력란에 채워집니다.';

    box.appendChild(header);
    box.appendChild(info);
    box.appendChild(chipArea);
    box.appendChild(footer);
    overlay.appendChild(box);

    overlay.addEventListener('click', function (e) {
      if (e.target === overlay) overlay.style.display = 'none';
    });

    document.body.appendChild(overlay);
    return overlay;
  }

  function renderChips(cards, divisionId, rawText) {
    var overlay = ensureModal();
    var info = document.getElementById(MODAL_ID + '_info');
    var chipArea = document.getElementById(MODAL_ID + '_chips');
    chipArea.innerHTML = '';

    if (!cards || cards.length === 0) {
      info.textContent = '사업부 [' + divisionId + '] 에 저장된 카드가 없습니다.';
      return;
    }
    info.textContent = '사업부 [' + divisionId + '] · 저장된 프로젝트 ' + cards.length + '개';

    cards.forEach(function (card, idx) {
      var chip = document.createElement('button');
      chip.type = 'button';
      var label = (card && card.title) ? String(card.title) : ('(제목없음 #' + (idx + 1) + ')');
      chip.textContent = label;
      chip.style.cssText = [
        'padding:8px 14px', 'background:#eff6ff', 'color:#1d4ed8',
        'border:1px solid #bfdbfe', 'border-radius:999px',
        'cursor:pointer', 'font-size:13px', 'font-weight:500'
      ].join(';');
      chip.addEventListener('mouseenter', function () {
        chip.style.background = '#dbeafe';
      });
      chip.addEventListener('mouseleave', function () {
        chip.style.background = '#eff6ff';
      });
      chip.addEventListener('click', function () {
        applyCard(card, rawText);
        overlay.style.display = 'none';
      });
      chipArea.appendChild(chip);
    });
  }

  function applyCard(card, rawText) {
    var ta = document.getElementById('noteRawText');
    if (!ta) {
      console.warn('[note_loader] #noteRawText not found');
      return;
    }

    // raw_text 가 있으면 그대로, 없으면 cardToText() 로 fallback
    ta.value = (rawText && String(rawText).trim()) ? String(rawText) : cardToText(card);

    // 미리보기 상태 초기화
    try {
      if (typeof _noteParsedCards !== 'undefined') {
        _noteParsedCards = null;
        window._noteParsedCards = null;
      }
    } catch (_) {}
    var pv = document.getElementById('notePreviewCard');
    if (pv) pv.style.display = 'none';
    var pvArea = document.getElementById('notePreviewArea');
    if (pvArea) pvArea.innerHTML = '';

    // 저장 버튼은 비활성 (AI 정리 다시 해야 활성화)
    var saveBtn = document.getElementById('noteSaveBtn');
    if (saveBtn) {
      saveBtn.disabled = true;
      saveBtn.style.opacity = '0.5';
    }

    var status = document.getElementById('noteStatus');
    if (status) {
      var t = (card && card.title) ? card.title : '(제목없음)';
      if (rawText && String(rawText).trim()) {
        status.textContent = '✅ [' + t + '] 저장된 원본 텍스트 불러옴 — 수정 후 "🤖 AI 정리" 를 눌러주세요';
        status.style.color = '#10b981';
      } else {
        status.textContent = '⚠️ [' + t + '] 저장된 원본 텍스트가 없어 카드 내용으로 복원됨';
        status.style.color = '#f59e0b';
      }
    }

    ta.focus();
    ta.scrollTop = 0;
  }

  async function openNoteLoadModal() {
    var sel = document.getElementById('noteDivision');
    var divisionId = sel ? sel.value : '';
    if (!divisionId) {
      alert('사업부를 먼저 선택하세요');
      return;
    }
    var overlay = ensureModal();
    var info = document.getElementById(MODAL_ID + '_info');
    var chipArea = document.getElementById(MODAL_ID + '_chips');
    chipArea.innerHTML = '';
    info.textContent = '불러오는 중...';
    overlay.style.display = 'flex';

    try {
      var r = await fetch('/notes?division_id=' + encodeURIComponent(divisionId));
      if (!r.ok) throw new Error('HTTP ' + r.status);
      var data = await r.json();
      var cards = (data && data.cards) || [];

      // 보고일자도 같이 채워 둠 (편의)
      if (data && data.report_date) {
        var dateEl = document.getElementById('noteReportDate');
        if (dateEl && !dateEl.value) dateEl.value = data.report_date;
      }
      renderChips(cards, divisionId, data && data.raw_text ? data.raw_text : '');
    } catch (e) {
      info.textContent = '❌ 불러오기 실패: ' + (e && e.message ? e.message : e);
      info.style.color = '#dc2626';
    }
  }

  window.openNoteLoadModal = openNoteLoadModal;
  console.log('[note_loader] loaded');
})();
