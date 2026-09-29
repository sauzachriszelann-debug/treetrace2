# How to Get TreeTrace Evaluation Metrics

Use these files for the final defense:

- `evaluation_test_results_template.csv`
- `evaluate_treetrace_results.py`
- `evaluation_outputs/treetrace_evaluation_report.md`
- `evaluation_outputs/species_confusion_matrix.csv`
- `YOLO_MAP_INSTRUCTIONS.md`

## Step 1: Test the App

Prepare labeled test images. For each image, record:

- actual species
- app predicted species
- actual conservation status
- app predicted conservation status
- actual DBH measured by tape
- app predicted DBH
- whether scan succeeded
- whether app workflow succeeded
- latency in milliseconds

## Step 2: Fill the CSV

Open:

```text
capstone/evaluation_test_results_template.csv
```

Replace the sample rows with your real test rows.

Use `1` for success and `0` for failed:

```text
scan_success,app_success
1,1
```

## Step 3: Run the Evaluation Script

From the project root:

```powershell
python capstone/evaluate_treetrace_results.py capstone/evaluation_test_results_template.csv
```

## Step 4: Use the Outputs

The script creates:

```text
capstone/evaluation_outputs/treetrace_evaluation_report.md
capstone/evaluation_outputs/species_confusion_matrix.csv
```

Use the report values in:

- Project Evaluation page
- documentation
- final PowerPoint
- defense discussion

## What This Calculates

- species accuracy
- macro F1-score
- F1-score per species
- confusion matrix
- conservation accuracy
- DBH MAE
- DBH RMSE
- scan success rate
- app success rate
- average latency

## YOLO mAP

YOLO mAP needs labeled YOLO validation data. If your group has labeled trunk/reference annotations, follow:

```text
capstone/YOLO_MAP_INSTRUCTIONS.md
```

If you do not have YOLO labels, do not claim mAP. Use DBH error against manual measurement instead.
