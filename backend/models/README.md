# TreeTrace DBH Segmentation Model

Place the trained YOLOv8 segmentation model here:

```text
backend/models/tree_trunk_segmentation.pt
```

Expected segmentation classes:

- `trunk` or `tree_trunk`
- `reference`, `reference_object`, `a4_paper`, `paper`, `id_card`, `card`, or `ruler`

The DBH pipeline uses this model only when the file exists. If the model is missing
or cannot detect both the trunk and reference object, TreeTrace falls back to the
existing AI-assisted DBH estimate.

Place the trained TreeTrace species classifier here:

```
backend/models/best_model.tflite
backend/models/labels.txt
```

These files are exported from the Colab notebook after comparing MobileNetV3Small,
EfficientNetB0, and ResNet50. The current TreeTrace integration expects the selected
ResNet50 export. When both files exist and TensorFlow or tflite-runtime is installed,
`/api/ai/identify` will use this local classifier before falling back to the online
AI identification pipeline.

## Phase 13.2 status (2026-10-25)

Neither file exists anywhere in this repository (verified by a project-wide search:
no species `.tflite`, no `labels.txt`, no training `.ipynb` — the only `.tflite`
files present are ML Kit barcode models inside `mobile/build/`). Until the Colab
export is added, `/api/ai/species-model-status` reports `ready: false` and every
scan depends on the external PlantNet/Gemini pipeline.

Exact contract the export must satisfy (from
`backend/app/services/local_species_classifier.py`):

- `backend/models/best_model.tflite` — the selected ResNet50 export, TFLite
  v1/v3 format readable by `tensorflow.lite.Interpreter` or
  `tflite_runtime.interpreter.Interpreter`.
  Input: `224 x 224 x 3` RGB, `float32` in `[0, 255]` (or `uint8` with the
  quantization scale/zero-point read from the tensor details).
  Output: a single softmax vector over the classes.
- `backend/models/labels.txt` — one plain species name per line, **in the exact
  class order of the model output** (line N = class index N). Empty lines are
  ignored.
- Runtime: `tensorflow` **or** `tflite-runtime` installed in the backend
  environment (neither is currently installed).

The integration and its mocked tests need no model file: the route honours
`local_species_model_status()["ready"]` and only calls
`classify_species_from_image()` when it is `True`.
