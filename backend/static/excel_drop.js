(function() {
  "use strict";

  window._excelPhotoMap = window._excelPhotoMap || {};

  const NL = String.fromCharCode(10);
  function getTextarea() { return document.getElementById("noteRawText"); }
  function getStatus() { return document.getElementById("noteStatus"); }

  function init() {
    const ta = getTextarea();
    if (!ta) return;

    ta.addEventListener("dragover", function(e) {
      const types = (e.dataTransfer && e.dataTransfer.types) || [];
      if (!Array.from(types).includes("Files")) return;
      e.preventDefault();
      ta.style.background = "#fef3c7";
    });
    ta.addEventListener("dragleave", function() { ta.style.background = ""; });

    ta.addEventListener("drop", async function(e) {
      ta.style.background = "";
      const files = Array.from((e.dataTransfer && e.dataTransfer.files) || []);
      const xls = files.filter(function(f) {
        const n = (f.name || "").toLowerCase();
        return n.endsWith(".xlsx") || n.endsWith(".xlsm");
      });
      if (xls.length === 0) return;
      e.preventDefault();

      const status = getStatus();
      const divisionId = (document.getElementById("noteDivision") || {}).value || "";
      if (!divisionId) {
        if (status) { status.textContent = "⚠️ 사업부를 먼저 선택하세요"; status.style.color = "#dc2626"; }
        return;
      }

      for (const f of xls) {
        if (status) { status.textContent = "📤 엑셀 변환 중: " + f.name; status.style.color = "#6b7280"; }
        try {
          const fd = new FormData();
          fd.append("division_id", divisionId);
          fd.append("file", f, f.name);
          const r = await fetch("/admin/notes/excel", { method: "POST", body: fd, credentials: "same-origin" });
          if (!r.ok) throw new Error("HTTP " + r.status);
          const data = await r.json();
          window._excelPhotoMap[f.name] = { photo_ref: data.photo_ref, url: data.url };

          const start = ta.selectionStart || 0;
          const before = ta.value.slice(0, start);
          const after = ta.value.slice(ta.selectionEnd || start);
          const needLeadNL = before.length > 0 && !before.endsWith(NL);
          const insertText = (needLeadNL ? NL : "") + "📷 " + f.name + " @@photo_ref=" + data.photo_ref + NL;
          ta.value = before + insertText + after;
          const pos = start + insertText.length;
          ta.selectionStart = ta.selectionEnd = pos;

          if (status) { status.textContent = "✅ 엑셀 변환 완료: " + f.name; status.style.color = "#10b981"; }
        } catch (err) {
          if (status) { status.textContent = "❌ 엑셀 업로드 실패: " + err.message; status.style.color = "#dc2626"; }
        }
      }
    });

    console.log("[excel_drop] init OK (as-photo)");
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
