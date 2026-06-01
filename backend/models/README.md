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
