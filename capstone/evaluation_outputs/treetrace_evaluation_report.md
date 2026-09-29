# TreeTrace Evaluation Results

## Summary
- Test images: 26
- Correct species predictions: 24/26
- Species accuracy: 92.31%
- Species macro F1-score: 0.952
- Correct conservation classifications: 25/26
- Conservation accuracy: 96.15%
- Measured DBH set: 26
- DBH MAE: +/- 2.12 cm
- DBH RMSE: 2.72 cm
- Scan success: 26/26 (100.00%)
- App success: 26/26 (100.00%)
- Average latency: 2114 ms

## F1-score per Species
| Species | Precision | Recall | F1-score | Support |
|---|---:|---:|---:|---:|
| Acacia | 1.000 | 0.500 | 0.667 | 2 |
| Baobab Tree | 1.000 | 1.000 | 1.000 | 2 |
| Brazilian copal | 1.000 | 1.000 | 1.000 | 1 |
| Crape-jasmine | 1.000 | 1.000 | 1.000 | 1 |
| Mahogany | 0.500 | 1.000 | 0.667 | 2 |
| Mango | 1.000 | 1.000 | 1.000 | 1 |
| Molave | 1.000 | 1.000 | 1.000 | 2 |
| Narra | 1.000 | 0.667 | 0.800 | 3 |
| Persimmon | 1.000 | 1.000 | 1.000 | 1 |
| Platymiscium | 1.000 | 1.000 | 1.000 | 1 |
| Raintree | 1.000 | 1.000 | 1.000 | 2 |
| Rauvolfia | 1.000 | 1.000 | 1.000 | 1 |
| Santol | 1.000 | 1.000 | 1.000 | 1 |
| Tamarind | 1.000 | 1.000 | 1.000 | 1 |
| Tasmanian bluegum | 1.000 | 1.000 | 1.000 | 1 |
| Teak | 1.000 | 1.000 | 1.000 | 1 |
| White-willow | 1.000 | 1.000 | 1.000 | 1 |
| Yakal | 1.000 | 1.000 | 1.000 | 2 |

## Confusion Matrix
Saved as `species_confusion_matrix.csv` in the same output folder.

## Defense Note
Use these values only after replacing the sample CSV rows with your group's actual test results.
For YOLO mAP, use labeled YOLO validation images and run the command in `YOLO_MAP_INSTRUCTIONS.md`.
