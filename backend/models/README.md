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
