# TreeTrace Data Mining Assignment Requirements

## Project Title

TreeTrace: AI-Assisted Mobile Tree Identification, Inventory, and Conservation Monitoring System

## Possible Application Area

The project belongs mainly to the Environment and Conservation area. It can also be connected to Agriculture, Education, Public Safety, Local Government, and Smart City monitoring because it helps identify, record, map, and protect trees in a community.

## General Problem Statement

Many communities and local government units still collect and manage tree information manually. Tree species, tree locations, health status, DBH, height, and protected classification are often recorded on paper or scattered files, making the data difficult to search, analyze, and use for decision-making. Because of this, endangered or protected trees may not be recognized immediately, community tree inventories may become incomplete, and field workers may spend more time validating information.

TreeTrace addresses this problem through a mobile application that collects tree photos and field information, processes the data, applies AI-assisted identification and classification techniques, and transforms the results into useful insights such as species prediction, conservation status, tree distribution, biodiversity summaries, DBH/height estimates, and do-not-cut warnings.

## Project Objectives

1. Identify a real-world problem from a selected area or industry.

TreeTrace identifies the problem of inefficient tree inventory, limited field-based species identification, and weak conservation monitoring in community and LGU tree management.

2. Collect and preprocess relevant data.

The system collects tree photos, common name, scientific name, DBH, height, health status, barangay, city, GPS coordinates, QR code links, health logs, and unknown species submissions. Image files are compressed and converted before being sent to the AI identification module.

3. Apply suitable data mining algorithms or techniques.

The system applies image classification, pattern recognition, species matching, rule-based conservation classification, DBH/height estimation, and biodiversity analysis.

4. Develop a functional mobile application.

TreeTrace includes a Flutter mobile app with login, registration, AI Tree Scanner, tree map, QR scanner, public tree profile, add tree, DBH measurement, community structure, upgrade, and profile screens.

5. Present meaningful insights, predictions, or recommendations.

The app presents species predictions, confidence level, estimated DBH and height, protected or endangered status, do-not-cut recommendations, tree map visualization, species distribution, barangay biodiversity report, Shannon Index, and top species per barangay.

6. Evaluate the performance and accuracy of the implemented model.

The project includes model confidence levels and DBH accuracy notes in the system. For final defense, formal evaluation should be documented using a test set of labeled tree images and field measurements. A suggested evaluation table is included in the Model Evaluation Results section below.

## Data Mining Technique Used

| Technique | How It Is Used in TreeTrace |
|---|---|
| Image Classification | Identifies possible tree species from uploaded or captured images. |
| Pattern Recognition | Analyzes visual features such as leaves, bark, trunk shape, crown form, flowers, and fruit. |
| Classification | Classifies trees by conservation status such as Critically Endangered, Endangered, Vulnerable, Protected, or Not Listed. |
| Prediction / Estimation | Estimates DBH, tree height, and possible species information from photos. |
| Descriptive Analytics | Summarizes tree counts, species distribution, barangay breakdown, and biodiversity values. |
| Data Visualization | Displays maps, charts, reports, and biodiversity summaries. |

## Algorithm Used

| Algorithm / Method | Purpose |
|---|---|
| PlantNet Image Matching | Provides botanical species suggestions from tree photos. |
| Gemini Vision AI | Confirms or enriches species identification and returns structured tree information. |
| YOLOv8 Segmentation / Detection | Supports trunk/reference detection for DBH measurement when enabled. |
| Rule-Based Classification | Checks whether a tree is protected, endangered, or allowed to be cut using the local species database. |
| Shannon Diversity Index | Measures biodiversity/community structure per barangay. |
| Allometric Carbon Formula | Estimates biomass/carbon value from DBH and height. |

## Dataset Used

| Dataset / Data Source | Use |
|---|---|
| User-collected tree photos | Main input for AI tree identification and unknown species submissions. |
| Tree inventory records | Stores species, DBH, height, health status, barangay, GPS coordinates, and photo URLs. |
| PlantNet botanical database | Supports species image matching. |
| Philippine protected/endangered species reference data | Used for conservation status and do-not-cut warnings. |
| TimberVision / trunk segmentation resources | Supports trunk detection and DBH-related measurement features. |
| Health log records | Tracks changes in DBH, height, health condition, and notes over time. |

## Required Mobile App Pages / Screens

These are the pages that should be shown during the assignment demonstration.

| Required Feature | TreeTrace Page / Screen |
|---|---|
| User-friendly interface | Splash, Login, Register, Dashboard, Public Portal |
| Data input and storage | Add Tree, AI Tree Scanner, DBH Measure, Health Logs |
| Data analysis module | AI Tree Scanner, Community Structure, DBH Measure |
| Visualization of results | Tree Map, Community Structure, Public Tree Profile, Dashboard |
| Data mining algorithm implementation | AI Tree Scanner, DBH Measure, backend AI identification endpoint |
| Testing/evaluation results | Model Evaluation Results section in this document and final presentation |
| Recommendation / warning | Do Not Cut warning, protected/endangered species alert |
| Dataset/history review | Unknown Species Review, Tree List, Health Logs |

## Important App Pages to Present

### Mobile App

1. Splash Screen
2. Login Screen
3. Register Screen
4. Dashboard
5. Public Portal
6. Tree Map
7. AI Tree Scanner
8. Add Tree
9. DBH Measure
10. Scan QR
11. Public Tree Profile
12. Tree List
13. Tree Detail
14. Health Logs
15. Community Structure
16. Profile

### Web/Admin Dashboard

1. Dashboard
2. Tree List
3. Add Tree
4. Tree Detail
5. Tree Map
6. AI Identify
7. Community Structure
8. Reports and Tools
9. QR Manager
10. Health Logs
11. Unknown Species Review
12. Admin Users

## Meaningful Insights, Predictions, and Recommendations

| Output Type | Where It Appears | Example |
|---|---|---|
| Species prediction | AI Tree Scanner | Common name and scientific name of the tree. |
| Confidence level | AI Tree Scanner | High, Medium, or Low confidence. |
| DBH prediction | AI Tree Scanner / DBH Measure | Estimated DBH in centimeters. |
| Height prediction | AI Tree Scanner / Add Tree | Estimated tree height in meters. |
| Conservation recommendation | AI Tree Scanner / Tree Detail | Do Not Cut warning for protected species. |
| Biodiversity insight | Community Structure | Shannon Index and species count per barangay. |
| Distribution insight | Tree Map / Community Structure | Number of trees per barangay and species distribution. |
| Care/ecological information | Public Tree Profile / AI Tree Scanner | Habitat, uses, and ecological value. |
| Carbon estimate | Add Tree / Reports | Estimated carbon based on DBH and height. |

## Model Evaluation Results

### Evaluation Goal

The evaluation checks whether the AI-assisted data mining module can correctly identify tree species, classify conservation status, and provide useful DBH/height estimates.

### Evaluation Dataset

For final testing, prepare a small labeled test set:

- 30 tree images from different species
- Each image should have a known correct common name and scientific name
- At least 5 images should contain protected or endangered species if available
- At least 10 images should include field-measured DBH values for comparison

### Evaluation Metrics

| Metric | Formula / Basis | Purpose |
|---|---|---|
| Species Identification Accuracy | Correct species predictions / Total test images x 100 | Measures how often the AI identifies the correct tree. |
| Conservation Classification Accuracy | Correct protected/not protected classifications / Total test images x 100 | Measures how often the system gives the correct conservation warning. |
| DBH Mean Absolute Error | Average of absolute difference between actual DBH and predicted DBH | Measures DBH estimate error. |
| Confidence Distribution | Count of High, Medium, and Low confidence results | Shows how confident the model is during testing. |
| Usability Result | Successful scans / Total scan attempts x 100 | Measures whether the app can complete the AI scan process reliably. |

### Evaluation Scope Used in the App

For the current TreeTrace prototype, the Project Evaluation page should report only metrics that the group can verify during testing:

- Species classification accuracy
- Conservation classification accuracy
- DBH measurement error against manual tape measurement
- Scan success rate
- App workflow success rate

Do not claim mAP, F1-score, confusion matrix, latency, or CNN training results unless the group has actually trained/evaluated the model and recorded those values. It is acceptable to mention YOLO for trunk/reference detection and AI vision/image classification for species identification, while presenting manual test results for the final defense.

### Suggested Test Result Table

Use this table during actual testing. Replace the sample values with your group test results.

| Test Item | Sample Result Format |
|---|---|
| Number of test images | 30 images |
| Correct species predictions | 24 out of 30 |
| Species identification accuracy | 80% |
| Correct conservation classifications | 28 out of 30 |
| Conservation classification accuracy | 93.33% |
| Images with measured DBH | 10 images |
| Average DBH error | +/- 10 to 30 cm |
| High confidence results | 14 images |
| Medium confidence results | 10 images |
| Low confidence results | 6 images |
| Successful app scan attempts | 30 out of 30 |
| App scan success rate | 100% |

### Evaluation Interpretation

The model is useful for field assistance because it can provide quick species suggestions, confidence levels, conservation warnings, and approximate DBH/height estimates. However, the system should not be treated as a final botanical authority when confidence is low. Low-confidence or unknown species results should be submitted for expert review. DBH and height estimates should also be validated using manual field measurement, especially for official inventory and compliance reports.

### Current System Evidence

The current system already shows evaluation-related output in these areas:

| Evidence | Location |
|---|---|
| AI confidence level | AI Tree Scanner result screen |
| DBH accuracy note | DBH Measure and AI-assisted DBH estimate |
| Protected/endangered status | AI Tree Scanner and Tree Detail |
| Biodiversity metrics | Community Structure screen |
| Species distribution charts | Community Structure screen |
| Inventory report validation note | Reports and Tools |

## Expected Deliverables Status

| Deliverable | TreeTrace Status |
|---|---|
| Project Proposal | Available through capstone documentation and this assignment requirements file. |
| Mobile Application Prototype/System | Available in the Flutter mobile app folder. |
| Source Code | Available in mobile, backend, and frontend folders. |
| Documentation | Available in capstone documents and system overview files. |
| Dataset Used | Described in this document; actual images/records come from field/user collection and API references. |
| Final Presentation and Demonstration | Should demonstrate AI scan, add tree, map, QR scan, community structure, reports, and model evaluation results. |

## Recommended Final Demonstration Flow

1. Open the mobile app and log in.
2. Open AI Tree Scanner and upload or capture a tree photo.
3. Show the predicted species, confidence level, DBH/height estimate, and conservation status.
4. If the species is protected, show the Do Not Cut warning.
5. Add the result to the tree inventory or submit it for expert review.
6. Open the Tree Map to show GPS-based visualization.
7. Open Community Structure to show biodiversity analysis and species distribution.
8. Open Reports and Tools to show inventory report/export.
9. Present the Model Evaluation Results table from this document.
