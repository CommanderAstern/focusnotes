"""Verification only. Run once in build/embed-venv; never used by the engine.
python3 -m venv build/embed-venv && build/embed-venv/bin/pip install -r Sources/EmbedChecks/requirements-reference.txt
HF_HOME=build/hf-cache build/embed-venv/bin/python Sources/EmbedChecks/generate-reference.py
Requires tokenizers, sentence-transformers 6.1+, transformers 5.19+, torch, pillow.
"""
from pathlib import Path
import hashlib
import json
import importlib.metadata
import numpy as np
import torch
from PIL import Image, ImageDraw, ImageFont
from tokenizers import Tokenizer
from sentence_transformers import SentenceTransformer

OUT = Path(__file__).parent / "Fixtures"
OUT.mkdir(exist_ok=True)
MODEL_REVISION = "914f7f89142e33e77833254d9c9b90c3cef7303b"
ONNX_REVISION = "daa72c51243991dfcaf9f9137d2c573d8f7790c0"
strings = [
    "Hello world", "", "Hello, world! (yes/no) — 42.5%", "  leading and trailing  ",
    "let value = foo(bar: 42)\n// Swift 🦉", "fn main() { println!(\"hi\"); }",
    "👨‍👩‍👧‍👦 🚀 café ☕️", "中文搜索与日本語のメモ", "Café naïve résumé Ångström",
    "Cafe\u0301 decomposed a\u0308", "a" + " " * 128 + "b\n" * 64 + "\t" * 64,
    "<bos>literal<eos><|image|><image|>", "\x00\u0378\U0010ffff byte fallback",
    "task: search result | query: how do token buckets limit requests",
    "title: none | text: Async Rust borrows across await boundaries.",
]
tokenizer = Tokenizer.from_file("build/models/tokenizer.json")
tokens = [{"text": text, "ids": tokenizer.encode(text).ids} for text in strings]
tokenizer.enable_truncation(max_length=2048)
long_text = "hello 🌍 " * 1500
tokens.append({"text": long_text, "ids": tokenizer.encode(long_text).ids})
(OUT / "tokenizer.json").write_text(json.dumps({
    "revision": ONNX_REVISION, "tokenizers_version": importlib.metadata.version("tokenizers"),
    "tokenizer_sha256": hashlib.sha256(Path("build/models/tokenizer.json").read_bytes()).hexdigest(),
    "cases": tokens,
}, ensure_ascii=True, indent=2) + "\n")

font_path = "/System/Library/Fonts/Supplemental/Arial.ttf"
font = ImageFont.truetype(font_path, 28)
title_font = ImageFont.truetype(font_path, 40)
image = Image.new("RGB", (960, 480), "white")
d = ImageDraw.Draw(image)
d.text((230, 24), "TOKEN BUCKET RATE LIMITER", fill="black", font=title_font)
d.rectangle((300, 140, 620, 350), outline="black", width=5)
d.text((365, 160), "Token bucket", fill="black", font=font)
for x in [365, 430, 495, 560]: d.ellipse((x-16, 240, x+16, 272), fill="#4477aa")
d.text((24, 220), "Requests", fill="black", font=font)
d.line((155, 252, 286, 252), fill="black", width=5)
d.polygon([(286,252),(266,240),(266,264)], fill="black")
d.line((635, 252, 782, 252), fill="black", width=5)
d.polygon([(782,252),(762,240),(762,264)], fill="black")
d.text((792, 220), "Allowed", fill="black", font=font)
d.text((260, 400), "Refill tokens at a fixed rate; limit requests", fill="black", font=font)
image.save(OUT / "token-bucket.png")
chart = Image.new("RGB", (960, 480), "white")
d = ImageDraw.Draw(chart)
d.text((210, 24), "MONTHLY SALES BAR CHART", fill="black", font=title_font)
d.line((130, 100, 130, 400, 860, 400), fill="black", width=4)
for i, (label, height) in enumerate([("Jan",120),("Feb",220),("Mar",170),("Apr",280)]):
    x = 220 + i*160
    d.rectangle((x,400-height,x+90,398), fill="#4477aa")
    d.text((x+15,412), label, fill="black", font=font)
chart.save(OUT / "bar-chart.png")

texts = [
    {"text": "how do token buckets limit requests", "kind": "query", "title": None},
    {"text": "Rust lifetimes express how long references are valid. Async tasks and await can expose borrow checker problems when references outlive their owners.", "kind": "document", "title": "Rust lifetimes"},
    {"text": "Café recipes: espresso, steamed milk and crème brûlée.", "kind": "document", "title": None},
]
torch.set_num_threads(4)
model = SentenceTransformer("google/embeddinggemma-2", revision=MODEL_REVISION, device="cpu",
    config_kwargs={"audio_config": None},
    model_kwargs={"dtype": torch.float32, "attn_implementation": "eager"})

def truncate(vector):
    vector = np.asarray(vector, dtype=np.float32)[:256]
    return (vector / np.linalg.norm(vector)).tolist()

for item in texts:
    prefix = "task: search result | query: " if item["kind"] == "query" else f"title: {item['title'] or 'none'} | text: "
    item["vector"] = truncate(model.encode(prefix + item["text"], normalize_embeddings=True))
    print("Reference text:", item["text"], flush=True)
vector = truncate(model.encode({"image": str(OUT / "token-bucket.png")}, normalize_embeddings=True))
fixture = {"model": "google/embeddinggemma-2", "revision": MODEL_REVISION,
    "dtype": "float32", "backend": "official SentenceTransformer mean pooling + normalize; torchvision antialias bicubic default image processor",
    "versions": {p: importlib.metadata.version(p) for p in ["torch", "torchvision", "transformers", "sentence-transformers", "tokenizers", "pillow", "numpy"]},
    "dimensions": 256, "texts": texts, "image": {"file": "token-bucket.png", "vector": vector}}
(OUT / "embeddings.json").write_text(json.dumps(fixture, ensure_ascii=True, indent=2) + "\n")
print("Reference fixtures written", flush=True)
