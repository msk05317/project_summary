"""
FAISS 벡터스토어 로드 및 검색 유틸
"""
import json
import os
from pathlib import Path
from typing import Optional
import numpy as np
import faiss
from openai import OpenAI

BASE = Path(__file__).parent.parent
DATA_DIR = Path(os.getenv("DATA_DIR", str(BASE)))
RAG_DIR = DATA_DIR / "rag"
RAG_DIR.mkdir(parents=True, exist_ok=True)
INDEX_PATH = RAG_DIR / "vector_index.faiss"
META_PATH = RAG_DIR / "vector_meta.json"

EMBED_MODEL = "text-embedding-3-small"

_client: Optional[OpenAI] = None
_index: Optional[faiss.Index] = None
_meta: Optional[list] = None


def _get_client() -> OpenAI:
    global _client
    if _client is None:
        _client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))
    return _client


def _load():
    """인덱스와 메타를 lazy 로드"""
    global _index, _meta
    if _index is None and INDEX_PATH.exists():
        _index = faiss.read_index(str(INDEX_PATH))
    if _meta is None and META_PATH.exists():
        _meta = json.loads(META_PATH.read_text(encoding="utf-8"))


def is_ready() -> bool:
    _load()
    return _index is not None and _meta is not None


def search(query: str, top_k: int = 5) -> list[dict]:
    """
    쿼리 임베딩 -> Top-K 검색
    반환: [{score, division_id, project_key, project_label, report_date, text}, ...]
    """
    _load()
    if _index is None or _meta is None:
        return []

    resp = _get_client().embeddings.create(model=EMBED_MODEL, input=[query])
    qv = np.array([resp.data[0].embedding], dtype=np.float32)
    faiss.normalize_L2(qv)

    scores, ids = _index.search(qv, top_k)
    results = []
    for score, idx in zip(scores[0], ids[0]):
        if idx < 0 or idx >= len(_meta):
            continue
        m = dict(_meta[idx])
        m["score"] = float(score)
        results.append(m)
    return results
