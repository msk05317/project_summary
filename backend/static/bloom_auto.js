(function () {
  const $ = (id) => document.getElementById(id);

  function esc(v) {
    return String(v ?? '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
  }

  function dotClass(status) {
    if (status === 'red') return 'red';
    if (status === 'yellow') return 'yellow';
    if (status === 'green') return 'green';
    return 'gray';
  }

  function statusText(status, label) {
    if (status === 'red') {
      if (label && label.includes('부족')) return '🔴 부족';
      return '🔴';
    }
    if (status === 'yellow') return '🟡';
    if (status === 'green') return '🟢';
    if (label && label.includes('점검 대상 없음')) return '회색 (점검 없음)';
    if (label && label.includes('미발주')) return '회색';
    return '회색';
  }

  function extractSubDetail(step, kind, product) {
    const label = step?.label || '-';
    const pct = step?.pct ?? 0;

    const explicitMap = {
      material: product?.material_detail || '',
      inbound: product?.inbound_detail || '',
      production: product?.production_detail || '',
      delivery: product?.delivery_detail || ''
    };
    if (explicitMap[kind]) return explicitMap[kind];

    if (pct >= 100) return '';
    if (!label || label === '-') return '';

    if (kind === 'material') {
      if (label.includes('점검 대상 없음')) return '';
      if (label.includes('미발주')) return '미발주';
      if (label.includes('부족')) return '';
      return label;
    }

    if (kind === 'inbound') {
      if (label === '-') return '';
      return label;
    }

    if (kind === 'production') {
      let t = label;
      t = t.replace(/^\d[\d,]*\s*\/\s*\d[\d,]*/,'').trim();
      t = t.replace(/\(\d+(?:\.\d+)?%\)$/,'').trim();
      return t && t !== label ? t : '';
    }

    if (kind === 'delivery') {
      const m = label.match(/잔량\s*([\d,]+)/);
      if (m) return `잔량 ${m[1]}`;
      return '';
    }

    return '';
  }

  function compactCell(step, kind, product) {
    const status = step?.status || 'gray';
    const pct = step?.pct ?? 0;
    const fraction = step?.fraction || '-';
    const label = step?.label || '-';
    const sub = extractSubDetail(step, kind, product);

    if (kind === 'material') {
      if (label.includes('점검 대상 없음')) {
        return `<div class="cell-main">회색 (점검 없음)</div>`;
      }
      if (label.includes('미발주')) {
        return `
          <div class="cell-main">회색</div>
          <div class="cell-sub">미발주</div>
        `;
      }
      if (label.includes('부족')) {
        return `
          <div class="cell-main">🔴 부족 ${esc(fraction)}</div>
          ${sub ? `<div class="cell-sub">${esc(sub)}</div>` : ''}
        `;
      }
      return `
        <div class="cell-main">회색</div>
        ${sub ? `<div class="cell-sub">${esc(sub)}</div>` : ''}
      `;
    }

    if (kind === 'inbound') {
      return `
        <div class="cell-main">회색</div>
        ${sub ? `<div class="cell-sub">${esc(sub)}</div>` : ''}
      `;
    }

    const badge = statusText(status, label);
    return `
      <div class="cell-main">${badge} ${esc(fraction)} ${esc(String(pct))}%</div>
      ${sub ? `<div class="cell-sub">${esc(sub)}</div>` : ''}
    `;
  }

  function renderPreviewTable(card) {
    if (!card) return '<div style="color:#dc2626;">렌더할 카드 데이터가 없습니다.</div>';
    const products = Array.isArray(card.products) ? card.products : [];

    return `
      <div class="bloom-preview-card">
        <div class="bloom-preview-header">
          <div class="bloom-preview-title">${esc(card.title || '<블룸>')}</div>
          ${card.badge ? `<div class="bloom-preview-badge">${esc(card.badge)}</div>` : ''}
        </div>

        <table class="bloom-preview-table">
          <thead>
            <tr>
              <th>제품</th>
              <th>원자재</th>
              <th>입고</th>
              <th>생산</th>
              <th>납기</th>
            </tr>
          </thead>
          <tbody>
            ${products.map(p => `
              <tr>
                <td>${esc(p.name || '')}</td>
                <td>${compactCell(p.material, 'material', p)}</td>
                <td>${compactCell(p.inbound, 'inbound', p)}</td>
                <td>${compactCell(p.production, 'production', p)}</td>
                <td>${compactCell(p.delivery, 'delivery', p)}</td>
              </tr>
            `).join('')}
          </tbody>
        </table>
      </div>
    `;
  }

  function renderBloomCard(card) {
    return renderPreviewTable(card);
  }

  function pickFiles() {
    const a = $('bloomPoFile')?.files?.[0];
    const b = $('bloomBopFile')?.files?.[0];
    const c = $('bloomKpeFile')?.files?.[0];
    return [a, b, c].filter(Boolean);
  }

  async function postBloom(url) {
    const files = pickFiles();
    if (files.length === 0) {
      alert('엑셀 파일을 1개 이상 선택하세요.');
      return null;
    }
    const fd = new FormData();
    files.forEach(f => fd.append('files', f));
    const res = await fetch(url, { method: 'POST', body: fd, credentials: 'include' });
    const text = await res.text();
    let data;
    try { data = JSON.parse(text); }
    catch (e) { throw new Error(text || '응답 파싱 실패'); }
    if (!res.ok || data.ok === false) {
      const msg = data?.detail?.message || data?.detail || data?.message || '요청 실패';
      throw new Error(typeof msg === 'string' ? msg : JSON.stringify(msg));
    }
    return data;
  }

  function adaptToCard(data) {
    if (data?.card) return data.card;
    const note = data?.note || {};
    const products = Array.isArray(note.products) ? note.products : [];
    function step(s) {
      if (!s) return { status: 'gray', pct: 0, fraction: '-', label: '-' };
      return {
        status: s.status || 'gray',
        pct: s.pct ?? 0,
        fraction: s.fraction || '-',
        label: s.label ?? '-'
      };
    }
    return {
      title: note.title || '<블룸>',
      badge: (note.status_hint === 'RED') ? 'RISK' : '',
      issues: Array.isArray(note.issues) ? note.issues : [],
      products: products.map(p => ({
        name: p.name || p.product || '',
        material: step(p.material),
        inbound: step(p.inbound),
        production: step(p.production),
        delivery: step(p.delivery),
        material_detail: p.material_detail || ''
      }))
    };
  }

  function showCard(data) {
    const wrap = $('bloomPreviewWrap');
    const mount = $('bloomPreviewMount');
    if (!wrap || !mount) return;
    wrap.style.display = 'block';
    mount.innerHTML = renderBloomCard(adaptToCard(data));
  }

  async function doPreview() {
    $('bloomAutoStatus').textContent = '미리보기 생성 중...';
    try {
      const data = await postBloom('/admin/notes/bloom/auto_generate');
      if (data) {
        showCard(data);
        $('bloomAutoStatus').textContent = '미리보기 완료';
      } else {
        $('bloomAutoStatus').textContent = '';
      }
    } catch (err) {
      $('bloomAutoStatus').textContent = '미리보기 실패';
      alert(err.message);
    }
  }

  async function doSave() {
    $('bloomAutoStatus').textContent = '저장 중...';
    try {
      const data = await postBloom('/admin/notes/bloom/auto_save');
      if (data) {
        showCard(data);
        $('bloomAutoStatus').textContent = '저장 완료 ✅';
      } else {
        $('bloomAutoStatus').textContent = '';
      }
    } catch (err) {
      $('bloomAutoStatus').textContent = '저장 실패';
      alert(err.message);
    }
  }

  function toggleCardByDivision() {
    const sel = $('noteDivision');
    const card = $('bloomAutoCard');
    if (!sel || !card) return;
    const v = (sel.value || '').toLowerCase();
    card.style.display = (v === 'bloom' || v === '블룸') ? 'block' : 'none';
  }

  function init() {
    $('bloomPreviewBtn')?.addEventListener('click', doPreview);
    $('bloomSaveBtn')?.addEventListener('click', doSave);
    const divSel = $('noteDivision');
    if (divSel) {
      divSel.addEventListener('change', toggleCardByDivision);
      toggleCardByDivision();
      let tries = 0;
      const t = setInterval(() => {
        toggleCardByDivision();
        if (++tries > 20) clearInterval(t);
      }, 500);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
