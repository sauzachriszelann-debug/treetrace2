# YOLO mAP Evaluation for TreeTrace

Use this only if your group has a labeled YOLO validation dataset with trunk/reference annotations.

## Required Files

Prepare a YOLO dataset folder like this:

```text
yolo_dataset/
  images/
    train/
    val/
  labels/
    train/
    val/
  data.yaml
```

For segmentation models, the label files must use YOLO segmentation format. For detection models, use YOLO bounding box format.

## Example data.yaml

```yaml
path: C:/Users/Chris Zel Ann/Documents/Treetrace/yolo_dataset
train: images/train
val: images/val

names:
  0: trunk
  1: reference_object
```

## Run mAP Validation

From the project root:

```powershell
yolo segment val model=backend/models/tree_trunk_segmentation.pt data=capstone/yolo_data_template.yaml imgsz=1024
```

If your model is a detection model instead of segmentation, use:

```powershell
yolo detect val model=backend/models/tree_trunk_segmentation.pt data=capstone/yolo_data_template.yaml imgsz=1024
```

## Metrics to Record

Record these from the YOLO output:

- Precision
- Recall
- mAP50
- mAP50-95

For the defense, say:

> YOLO mAP was evaluated only if labeled trunk/reference validation annotations were available. Otherwise, TreeTrace reports DBH error against manual DBH measurements instead.
