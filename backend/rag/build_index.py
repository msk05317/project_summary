"""
FAISS 벡터 인덱스 빌드 스크립트
notes.json -> 프로젝트 카드 단위로 청킹 -> OpenAI 임베딩 -> FAISS 저장
"""
import json
import os
from pathlib import Path
import numpy as np
import faiss
from openai import OpenAI
from dotenv import load_dotenv

load_dotenv()

BASE = Path(__file__).parent.parent
NOTES_PATH = BASE / "notes.json"
INDEX_PATH = BASE / "rag" / "vector_index.faiss"
META_PATH = BASE / "rag" / "vector_meta.json"

EMBED_MODEL = "text-embedding-3-small"
EMBED_DIM = 1536

client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))


def build_chunks(notes_data: dict) -> list[dict]:
    """
    notes.json -> 청크 리스트로 변환
    각 프로젝트 카드 = 1 청크 (raw_text 사용)
    """
    chunks = []
    notes = notes_data.get("notes", {})
    for division_id, div in notes.items():
        report_date = div.get("report_date", "")
        for card in div.get("cards", []):
            title = card.get("title", "")
            raw = (card.get("raw_text") or "").strip()
            if not raw:
                sections_text = []
                for sec in card.get("sections", []):
                    sec_title = sec.get("title", "")
                    for it in sec.get("items", []):
                        t = (it.get("text") or "").strip()
                        if t:
                            sections_text.append(f"- {t}")
                raw = f"<{title}>\n" + "\n".join(sections_text)

            if not raw or len(raw) < 20:
                continue

            chunks.append({
                "division_id": division_id,
                "project_key": title.lower().replace(" ", "_"),
                "project_label": title,
                "report_date": report_date,
                "text": raw,
            })
    return chunks


def embed_batch(texts: list[str]) -> np.ndarray:
    """OpenAI 임베딩 배치 호출"""
    resp = client.embeddings.create(model=EMBED_MODEL, input=texts)
    vecs = [d.embedding for d in resp.data]
    return np.array(vecs, dtype=np.float32)


def main():
    print(f"Loading notes from {NOTES_PATH}")
    notes_data = json.loads(NOTES_PATH.read_text(encoding="utf-8"))
    chunks = build_chunks(notes_data)
    print(f"Built {len(chunks)} chunks")

    if not chunks:
        print("No chunks. Abort.")
        return

    print("Embedding...")
    texts = [c["text"] for c in chunks]
    batch_size = 32
    all_vecs = []
    for i in range(0, len(texts), batch_size):
        batch = texts[i:i + batch_size]
        vecs = embed_batch(batch)
        all_vecs.append(vecs)
        print(f"  {i+len(batch)}/{len(texts)}")
    matrix = np.vstack(all_vecs)
    print(f"Embedded matrix shape: {matrix.shape}")

    faiss.normalize_L2(matrix)
    index = faiss.IndexFlatIP(EMBED_DIM)
    index.add(matrix)
    faiss.write_index(index, str(INDEX_PATH))
    print(f"Wrote index: {INDEX_PATH}")

    META_PATH.write_text(
        json.dumps(chunks, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"Wrote meta: {META_PATH}")
    print(f"Total {len(chunks)} chunks indexed")


if __name__ == "__main__":
    main()
