# OCR spike results

- Runtime: .NET 10, RapidOcrNet 4.2.0, Microsoft.ML.OnnxRuntime 1.31.0 (win-arm64)
- Mac baseline: Vision `accurate` revision 3 on Version 27.0.1 (Build 26A434) (arm64)
- Corpus: 200 images, 10,046,277 PNG bytes; language coverage uses the language tags in the manifest
- CER: micro-average Levenshtein distance over NFC-normalized Unicode scalar values; whitespace collapsed before scoring
- RapidOcrNet timing: OCR plus classifier; one warm-up pass per recognizer language group, then one measured pass
- Arabic recognizer output is reversed into logical Unicode text order per detected line before reading-order joining and CER scoring
- Recognition assets were downloaded from the pinned ModelScope revision and SHA-256/byte-count checked before loading

## Language results

| Vision language | Model id | Mac CER | Windows CER¹ | Delta (points) | Mac p95 ms | Windows p95 ms |
|---|---|---:|---:|---:|---:|---:|
| ar-SA | `ppocrv5-arabic-mobile` | 2.61 % | 31.37 % | +28.76 | 97.9 | 325.5 |
| ars-SA | `ppocrv5-arabic-mobile` | 6.94 % | 28.42 % | +21.48 | 74.8 | 355.6 |
| cs-CZ | `ppocrv5-latin-mobile` | 0.77 % | 1.35 % | +0.58 | 71.1 | 343.8 |
| da-DK | `ppocrv5-latin-mobile` | 0.80 % | 1.80 % | +1.00 | 64.5 | 340.7 |
| de-DE | `ppocrv5-latin-mobile` | 0.60 % | 0.60 % | 0.00 | 58.9 | 410.2 |
| en-US | `ppocrv5-ch-mobile` | 0.49 % | 0.78 % | +0.29 | 59.0 | 970.1 |
| es-ES | `ppocrv5-latin-mobile` | 0.42 % | 0.17 % | -0.25 | 63.4 | 402.5 |
| fi-FI | `ppocrv5-latin-mobile` | 0.35 % | 1.75 % | +1.40 | 63.0 | 348.7 |
| fr-FR | `ppocrv5-latin-mobile` | 0.78 % | 0.35 % | -0.43 | 77.7 | 401.2 |
| hi-IN | `ppocrv5-devanagari-mobile` | 1.48 % | 48.10 % | +46.62 | 72.1 | 340.2 |
| id-ID | `ppocrv5-latin-mobile` | 0.38 % | 0.57 % | +0.19 | 64.7 | 456.6 |
| it-IT | `ppocrv5-latin-mobile` | 0.36 % | 0.54 % | +0.18 | 66.1 | 749.6 |
| ja-JP | `ppocrv5-ch-mobile` | 4.80 % | 3.52 % | -1.28 | 106.8 | 399.7 |
| ko-KR | `ppocrv5-korean-mobile` | 2.33 % | 3.99 % | +1.66 | 72.8 | 338.2 |
| mr-IN | `ppocrv5-devanagari-mobile` | 1.29 % | 38.49 % | +37.20 | 52.9 | 333.1 |
| ms-MY | `ppocrv5-latin-mobile` | 0.38 % | 0.57 % | +0.19 | 68.9 | 341.0 |
| nb-NO | `ppocrv5-latin-mobile` | 0.59 % | 1.39 % | +0.79 | 52.3 | 334.0 |
| nl-NL | `ppocrv5-latin-mobile` | 0.38 % | 0.56 % | +0.19 | 56.6 | 343.1 |
| nn-NO | `ppocrv5-latin-mobile` | 0.40 % | 1.60 % | +1.20 | 66.3 | 336.4 |
| no-NO | `ppocrv5-latin-mobile` | 0.59 % | 1.39 % | +0.79 | 69.1 | 340.4 |
| pl-PL | `ppocrv5-latin-mobile` | 0.93 % | 3.74 % | +2.80 | 57.7 | 350.9 |
| pt-BR | `ppocrv5-latin-mobile` | 0.74 % | 0.55 % | -0.18 | 62.7 | 590.4 |
| ro-RO | `ppocrv5-latin-mobile` | 0.35 % | 3.89 % | +3.54 | 61.1 | 342.2 |
| ru-RU | `ppocrv5-eslav-mobile` | 0.77 % | 0.96 % | +0.19 | 62.6 | 501.2 |
| sv-SE | `ppocrv5-latin-mobile` | 0.37 % | 1.68 % | +1.31 | 71.6 | 340.8 |
| th-TH | `ppocrv5-thai-mobile` | 1.52 % | 12.12 % | +10.61 | 74.5 | 338.2 |
| tr-TR | `ppocrv5-latin-mobile` | 0.79 % | 3.16 % | +2.37 | 67.3 | 357.7 |
| uk-UA | `ppocrv5-eslav-mobile` | 1.50 % | 3.18 % | +1.68 | 78.0 | 1185.6 |
| vi-VT | `ppocrv5-latin-mobile` | 0.37 % | 13.21 % | +12.84 | 72.4 | 348.0 |
| yue-Hans | `ppocrv5-ch-mobile` | 6.84 % | 5.13 % | -1.71 | 76.4 | 339.1 |
| yue-Hant | `ppocrv5-ch-mobile` | 6.84 % | 5.98 % | -0.85 | 66.9 | 489.3 |
| zh-Hans | `ppocrv5-ch-mobile` | 8.41 % | 5.09 % | -3.33 | 84.9 | 757.7 |
| zh-Hant | `ppocrv5-ch-mobile` | 8.72 % | 5.04 % | -3.68 | 90.1 | 369.1 |

¹ RapidOcrNet recognizer CER measured on this Mac as the Windows engine proxy.
Classifier agreement: **100.0 %** (gate ≥ 95%).
1920×1080 images: **77**; Mac Vision p95 OCR+classify: **83.1 ms**; RapidOcrNet p95 OCR+classify: **501.8 ms** (runner gate ≤ 1,500 ms).
CER gate: **FAIL** (RapidOcrNet ≤ Mac + 2.0 points per language group).
Failing groups: ar-SA (+28.76 points), ars-SA (+21.48 points), hi-IN (+46.62 points), mr-IN (+37.20 points), pl-PL (+2.80 points), ro-RO (+3.54 points), th-TH (+10.61 points), tr-TR (+2.37 points), vi-VT (+12.84 points).

## Fixture assertions

- Paragraph: PASS (capture before mountain, with a blank-line break)
- Code: PASS (`CaptureRecord` and `collectRecords`)

## Model research and size

All 33 Vision languages in this corpus map to one of the recognizers below. The Chinese model is the PP-OCRv5 default multilingual recognizer for Simplified/Traditional Chinese, English, Japanese and the two Yue corpus groups. Russian and Ukrainian use the East-Slavic recognizer. The RapidAI model list records PP-OCRv5 ONNX URLs and hashes at revision `v3.10.0`; PaddleOCR and RapidOCR publish Apache-2.0 licensing for these source and converted model assets.

Sources: [RapidAI PP-OCRv5 model list, URLs and hashes](https://github.com/RapidAI/RapidOCR/blob/v3.10.0/python/rapidocr/default_models.yaml), [RapidAI model licensing and PaddleOCR attribution](https://github.com/RapidAI/RapidOCR/blob/main/README.md), [PaddleOCR license](https://github.com/PaddlePaddle/PaddleOCR/blob/main/LICENSE), [PP-OCRv5 language support](https://github.com/RapidAI/RapidOCRDocs/blob/main/docs/model_list.md).

| Model id | ONNX bytes | Dictionary bytes | License | Revision | ONNX source URL |
|---|---:|---:|---|---|---|
| `ppocrv5-ch-mobile` | 16,631,306 | 74,012 | Apache-2.0 | `v3.10.0` | [ModelScope](https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve/v3.10.0/onnx/PP-OCRv5/rec/ch_PP-OCRv5_rec_mobile.onnx) |
| `ppocrv5-latin-mobile` | 7,904,513 | 1,634 | Apache-2.0 | `v3.10.0` | [ModelScope](https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve/v3.10.0/onnx/PP-OCRv5/rec/latin_PP-OCRv5_rec_mobile.onnx) |
| `ppocrv5-korean-mobile` | 13,488,748 | 47,451 | Apache-2.0 | `v3.10.0` | [ModelScope](https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve/v3.10.0/onnx/PP-OCRv5/rec/korean_PP-OCRv5_rec_mobile.onnx) |
| `ppocrv5-eslav-mobile` | 7,911,802 | 1,663 | Apache-2.0 | `v3.10.0` | [ModelScope](https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve/v3.10.0/onnx/PP-OCRv5/rec/eslav_PP-OCRv5_rec_mobile.onnx) |
| `ppocrv5-arabic-mobile` | 8,023,828 | 2,369 | Apache-2.0 | `v3.10.0` | [ModelScope](https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve/v3.10.0/onnx/PP-OCRv5/rec/arabic_PP-OCRv5_rec_mobile.onnx) |
| `ppocrv5-devanagari-mobile` | 7,940,361 | 1,943 | Apache-2.0 | `v3.10.0` | [ModelScope](https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve/v3.10.0/onnx/PP-OCRv5/rec/devanagari_PP-OCRv5_rec_mobile.onnx) |
| `ppocrv5-thai-mobile` | 7,915,294 | 1,767 | Apache-2.0 | `v3.10.0` | [ModelScope](https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve/v3.10.0/onnx/PP-OCRv5/rec/th_PP-OCRv5_rec_mobile.onnx) |

Common detector and orientation classifier from RapidOcrNet NuGet:

- `ch_PP-OCRv5_mobile_det.onnx`: 4,819,576 bytes
- `ch_PP-LCNet_x0_25_textline_ori_cls_mobile.onnx`: 1,018,508 bytes
- Native ORT: onnxruntime.dll (win-arm64, 17,507,640 bytes)

## Corpus files

Images were read from `conformance\ocr\corpus`. Language groups and exact text are from `manifest.json`; the Mac values are from the paired baseline JSON.
