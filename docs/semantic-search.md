# Local semantic engine

`EmbedKit`, `EmbedHelper`, and `EmbedChecks` are independent targets. Use
`EmbedClient` from the app: it launches the helper on demand, serializes async
requests over newline-delimited JSON, retries a failed transport once, and
returns normalized vectors decoded from base64 little-endian Float16. The
helper exits after 60 seconds idle (`--idle-seconds` overrides this for checks).
Only the helper loads models/runtime. CPU worker spinning and runtime telemetry
are disabled. Python and third-party Swift packages are absent at runtime.

## Artifacts

The downloader pins [the ONNX export](https://huggingface.co/onnx-community/embeddinggemma-2-ONNX)
to `daa72c51243991dfcaf9f9137d2c573d8f7790c0` and the official
[ONNX Runtime 1.31.0 arm64 release](https://github.com/microsoft/onnxruntime/releases/tag/v1.31.0)
(minimum macOS 14.0). Recorded SHA-256 values cover every artifact, including
license/notices. Matching files are reused; downloads verify before replacement.

| Files | Precision | Bytes combined | Decimal MB |
| --- | --- | ---: | ---: |
| `onnx/model_quantized.onnx` + `.onnx_data` | Q8 weights, float32 activations | 314,220,093 | 314.22 |
| `onnx/vision_encoder_q4.onnx` + `.onnx_data` | Q4 weights, float32 activations | 109,117,096 | 109.12 |
| `tokenizer.json` | BPE vocabulary/merges | 32,170,510 | 32.17 |
| `libonnxruntime.dylib` | Native arm64 | 44,830,288 | 44.83 |

Configs/license/notices add 0.35 MB; total download is approximately **500.69 MB**.
Q4 text was tested first: cosines 0.991523 / **0.988034** / 0.990065 failed the
required 0.99 parity. Q8 text with Q4 vision passes and retains the smaller vision
artifact. Q4 retains float32 activations throughout the CPU path; Q4F16 changes
activation precision. Model IDs include the revision and mixed quantization.
`CORT` contains the three required C API headers and MIT license; no runtime
library is linked at build time. Loading uses `dlopen` and `OrtGetApiBase`.

## Pipeline

[Google's prompts](https://ai.google.dev/gemma/docs/embeddinggemma/model_card_2):
queries use `task: search result | query: <q>`; documents use
`title: <title or none> | text: <text>`; images have no text prefix. The Swift
tokenizer implements literal-space replacement with `▁`, ranked BPE, byte
fallback, added tokens and BOS/EOS. Truncation keeps 2,048 tokens including
BOS/EOS. Vocabulary and merge strings use exact UTF-8 parsing: canonical String
equality and Foundation decoding lose distinctions in this vocabulary.

Image settings live in `processor_config.json.image_processor`; the separate
`preprocessor_config.json` describes audio. PNGs convert to RGB and resize with
antialiased bicubic interpolation, preserving aspect ratio within 280 soft
tokens and rounding dimensions down to multiples of 48. Pixels rescale by 1/255
without additional normalization. Row-major 16×16 RGB patches pack into
`[1,2520,768]`, with `[x,y]` positions and padding positions -1. Vision emits
512-d soft tokens. BOS/begin-image/image placeholders/end-image/EOS pass through
the **shared text graph**, substituting those features at placeholder positions.
The graph projects to 768-d, applies masked mean pooling including prompts and
special tokens, and normalizes. Swift normalizes, truncates to 256 (configurable
to 128/512/768), then normalizes again.

The separate SQLite file stores caller key, model ID, dims and Float16 blob:
**512 bytes per 256-d vector**. Search filters incompatible models/dimensions,
normalizes decoded vectors into a cached contiguous Float32 buffer, and computes
brute-force cosine scores with Accelerate. Writes invalidate the cache; SQLite
`data_version` detects writes from other connections.

The vector database also stores a model identity made from the embedding
dimensions and the names and byte sizes of the text and vision ONNX graph/data
files. Changing that identity clears stale vectors so reconciliation rebuilds
them. File sizes are read from metadata; the model files are not hashed.

The app links macOS's system SQLite and checks for FTS5 when the search index
opens. macOS 14 ships SQLite 3.43 or newer. The index uses no triggers, which
avoids the FTS5-in-trigger issue in SQLite versions before 3.44.

## Running and evidence

```sh
scripts/fetch-models.sh                         # default build/models
swift build --scratch-path .build-sol5 --target EmbedKit
swift build --scratch-path .build-sol5 --product EmbedHelper
swift run --scratch-path .build-sol5 EmbedChecks --models build/models
scripts/check-name.sh
```

Missing models produce a clear skip, exit 0. Build the helper first, or pass
`EmbedChecks --helper <executable>`. Production callers pass
`~/Library/Application Support/<bundle id>/models/` to downloader/client; get
the identifier from the app bundle or derive it from `Config/app.env` exactly
as `scripts/build-app.sh` does.

## App integration

The app depends on the existing `EmbedKit` target. `scripts/build-app.sh` copies
the `EmbedHelper` product under its own name into `Contents/MacOS/` and signs it
before signing the app. Production uses `Bundle.main` to find the helper;
SwiftPM self-tests can use the sibling executable. No model, tokenizer, vision
graph or ONNX runtime is loaded in the main app. The helper launches on demand
and exits 60 seconds after its last response; opening search sends a background
`ping` (which launches the process without loading models).

At launch and each status-menu refresh, cheap file-existence checks look for the
two text graph files, two vision graph files, tokenizer, processor config and
runtime dylib in `~/Library/Application Support/<bundle identifier>/models/`.
The disabled info item under Permissions shows **Semantic search: On** or
**Semantic search: Off (models not installed)**. Install using
`scripts/fetch-models.sh <that directory>`; no settings UI is required. Missing
models and inference failures leave capture, OCR, Recent and keyword search
available.

`SemanticIndexer` is a utility-priority actor coordinator. Successful capture
commits, launch sync, watcher-driven sync and OCR backfill request a run, debounced
two seconds after the last request. One job runs at a time; a request arriving
during a job schedules another reconciliation. Captures and the main actor never
wait for embeddings. `vectors.sqlite` is separate from the keyword cache, in the
app's state directory. Its keys are `<vault-relative note path>#<capture UUID>`
(lowercase UUID), or `<path>#loose-<zero-based parser ordinal>` for loose blocks.
Each run compares the current blocks with compatible vector keys, embeds missing
keys and prunes deleted ones. Existing keys are reused; edits to an existing
capture body or a loose paragraph at the same ordinal require rebuilding the
disposable vector cache to refresh that vector.

Text is sent in batches of at most 16 sharing the note title. Image blocks receive
an image vector plus an OCR document vector under `<key>#ocr` when OCR is nonempty.
Both image-block operations wait for AC power and nominal/fair thermal state
(`IOPSCopyPowerSourcesInfo` and `ProcessInfo.thermalState`). Deferred images retry
on the next run; OCR recognition remains part of the existing capture pipeline.
Vectors retain EmbedKit's 256-dimensional Float16 storage.

`VaultMonitor` starts the FSEvents watcher after launch sync and stops it when
termination begins. Captures (including journal replay), image asset writes and
session note creation mark their vault-relative paths before writing. The app's
refresh actor serializes index sync and OCR backfill; events received during a
pass set dirty flags and merge into one subsequent pass. Note changes and full
sync events sync the keyword index and schedule the normal semantic diff. Asset
events use the existing missing/outdated-OCR check and backfill path. Search-panel
opening skips redundant sync while the watcher is running, and retains a cheap
background sync if its stream failed to start. `--self-test` checks that an
external FileManager edit becomes searchable within five seconds without an
explicit sync, and that termination stops the stream.

The empty query still returns Recent. Nonempty queries run keyword and semantic
search concurrently. Query embedding has a 350 ms caller deadline, including
helper startup or a wait behind backfill. The deadline returns keyword-only for
that keystroke while the unstructured inference continues warming the helper.
Task groups are deliberately avoided for this race because leaving their scope
would wait for non-cancellable transport I/O. A successful query requests the
nearest 40 vectors, collapses `#ocr` to its block using the higher cosine, then
forms separate ranked text/loose and image lists. Three-list Reciprocal Rank
Fusion adds `1 / (60 + rank)` for one-based ranks from keyword, semantic text and
semantic image lists. Stable keys deduplicate results; keyword snippets retain
highlights, semantic-only snippets use the first 140 characters of body or OCR
without highlights. One Results section contains at most 40 rows.

```sh
swift build --scratch-path .build-sol6 --product EmbedHelper
swift run --scratch-path .build-sol6 App --self-test <empty-temp-directory>
swift run --scratch-path .build-sol6 App --self-test <another-empty-temp-directory> --models <models-directory>
```

The first self-test reports semantic search skipped. With models, the test embeds
its captures, checks image/OCR vectors when power permits, checks stale-key
removal and the nonblocking cold-query deadline, then requires “throttling API
traffic” to rank “Token buckets allow bursts” first with no keyword overlap.
Both modes check three-list fusion, deduplication and the result cap.

Fixtures were generated once with [the official SentenceTransformer pipeline](https://ai.google.dev/gemma/docs/embeddinggemma/multimodal-embeddinggemma-with-sentence-transformers),
Google revision `914f7f89142e33e77833254d9c9b90c3cef7303b`, float32 CPU inference
and the default torchvision processor. Versions/provenance are in JSON.
`generate-reference.py` is excluded from the Swift target and uses only the
throwaway `build/embed-venv` with `HF_HOME=build/hf-cache`.

All **16 tokenizer cases** pass, including Unicode, fallback, specials,
whitespace and truncation. Text cosines: **0.999965 / 0.999930 / 0.999961**;
image: **0.998944**. Token-bucket text ranks first, its diagram second; Rust
lifetimes and sourdough each rank first. Persistence, cache invalidation,
concurrent callers, errors, idle restart and forced-death restart pass.

Apple M4 / macOS 27.0.1 / Swift 6.4 debug / four inference threads:
**8.428 s** process cold start to first vector; **0.050 s** median warm query
(five calls); **6.023 s** first image including vision loading. Helper RSS:
**395.8 MiB text-only / 835.5 MiB text+vision**. Filesystem caches were warm.
Idle exit with a 3-second override: **3.14 s**. New sources have zero compiler
warnings; CLT emits missing developer framework/library search-path linker
warnings unrelated to these sources.

## Release dylib policy

Sign/notarize the helper and select a downloaded-runtime policy before release.
[Apple library validation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation)
normally requires Apple signing or the helper's Team ID. Options:

1. Download a runtime signed with the app's Developer ID, notarize its
   distribution, pin the signed bytes, and verify signature/Team ID before
   loading. Keep library validation enabled.
2. Give only the helper `com.apple.security.cs.disable-library-validation`,
   sign/notarize it, and enforce pinned digests or authenticated signatures
   before `dlopen`. A SHA-256 check alone does not satisfy library validation.
3. Distribute a separately signed/notarized helper and matching signed runtime;
   validate that distribution before installing it.

[Notarization guidance](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
Re-signing changes hashes: release manifests must match final signed artifacts.
