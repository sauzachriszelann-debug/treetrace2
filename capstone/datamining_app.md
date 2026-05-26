# I. Project Title

## TreeTrace

An AI-Assisted Mobile Tree Identification, DBH Measurement, and Conservation Monitoring System Using Data Mining Techniques

# II. Introduction

Tree inventory and conservation monitoring are important activities for communities, schools, local government units, and environmental organizations. However, traditional tree monitoring is often done manually through paper forms, spreadsheets, or scattered digital records. This makes it difficult to quickly identify tree species, monitor DBH and height, track health status, locate trees on a map, and recognize protected or vulnerable species during field work.

The problem becomes more serious when tree data is underutilized. A community may already have many tree records, photos, health notes, and location details, but without proper analysis, the information cannot easily support conservation decisions. Field workers may spend extra time verifying species, estimating measurements, and checking whether a tree is protected. As a result, vulnerable, endangered, or ecologically important trees may not be flagged immediately.

The core motivation for this project is to develop a mobile application that makes tree monitoring easier, faster, and more useful. TreeTrace applies AI-assisted image classification, YOLO-supported trunk detection, pattern recognition, classification, prediction or estimation, and descriptive analytics to transform collected tree data into meaningful insights. Through the mobile app, users can add tree records, scan tree images, measure DBH, view map-based inventory data, receive conservation warnings, and check model evaluation results.

TreeTrace is designed as a practical data mining mobile application because it demonstrates how data can be collected, processed, analyzed, visualized, and evaluated. The system does not only store tree information; it uses the data to generate predictions, classifications, recommendations, and reports that support conservation and biodiversity monitoring.

# III. Project Objectives

## General Objective

To develop a mobile tree monitoring application that uses data mining techniques, AI-assisted image classification, YOLO-supported trunk detection, and biodiversity analytics to help users identify, measure, record, analyze, and protect trees in a community-based inventory system.

## Specific Objectives

1. **Tree Inventory Data Collection:** Implement a mobile data input feature that allows users to add tree records with common name, scientific name, DBH, height, health status, barangay, GPS location, notes, and tree photo.

2. **AI-Assisted Species Identification:** Develop an AI Tree Scanner that processes tree images and returns species predictions, scientific name, confidence level, and conservation information.

3. **DBH Measurement Support:** Integrate a DBH Measure feature that helps estimate tree diameter at breast height using image-based guidance, trunk/reference detection, and manual validation support.

4. **Conservation Classification:** Apply classification rules to identify trees as Least Concern, Vulnerable, Endangered, Protected, or requiring special conservation attention.

5. **Community Structure and Visualization:** Provide dashboards, maps, biodiversity summaries, species distribution, barangay breakdown, carbon estimates, and conservation alerts.

6. **Model Evaluation and Testing:** Present evaluation results using test rows that compare actual vs predicted species, actual vs predicted conservation status, actual vs predicted DBH, scan success, app success, and latency.

# IV. System Scope and Limitations

## Scope

This study focuses on the design, development, and implementation of TreeTrace, a mobile and web-supported tree monitoring system that applies data mining techniques to environmental conservation.

1. **Deployment Environment:** The system is designed for a Flutter mobile application supported by a backend API and web/admin dashboard. The mobile app is used for field data collection, scanning, DBH measurement, map viewing, reports, and project evaluation.

2. **Target Users:** The application is intended for field workers, students, researchers, school communities, local government users, environmental groups, and citizens who need to monitor tree records and conservation status.

3. **Core Functionalities:** The system includes login and registration, dashboard, AI Tree Scanner, Add Tree, DBH Measure, Tree Map, QR scanning, Public Tree Profile, Health Logs, Community Structure, Reports and Tools, Unknown Species Review, and Project Evaluation.

4. **Data Integration:** The system stores tree inventory records, tree images, DBH and height values, health logs, GPS location, conservation categories, evaluation rows, and unknown species submissions.

5. **Data Mining Coverage:** The project applies image classification, pattern recognition, classification, prediction or estimation, descriptive analytics, data visualization, and YOLO-supported object detection.

## Limitations

To keep the project achievable, focused, and reliable, the following limitations are recognized:

1. **Not a Final Botanical Authority:** TreeTrace provides AI-assisted species suggestions, but low-confidence or unknown results should still be reviewed by an expert or admin.

2. **DBH Measurement Accuracy:** Image-based DBH estimates are useful for field assistance, but official DBH records should still be validated using manual tape measurement at 1.3 meters from the ground.

3. **YOLO Dependency:** YOLO-based DBH segmentation only works when the required model, dependencies, and backend setting are properly enabled.

4. **Image Quality Constraints:** Species prediction and trunk detection may be affected by blurry images, poor lighting, obstructed trunks, wrong camera angle, or missing reference objects.

5. **Dataset Scope:** Evaluation results are based on the available test CSV and database rows. The accuracy may change if more images, more species, or more field measurements are added.

6. **Internet and Backend Dependency:** Some AI and database features require the backend server and network connection to be running properly.

# V. Data Mining Engine

## Image Classification and Pattern Recognition Architecture

1. **Purpose:** TreeTrace uses image-based analysis to identify tree species and recognize visual patterns from tree photos. These patterns may include trunk shape, bark texture, leaves, crown structure, and reference object position.

2. **Data Mining Technique:** The system uses Image Classification and Pattern Recognition to convert tree images into useful prediction results.

3. **Input Data:** The input may come from a live camera capture or uploaded image.

4. **Output Data:** The output includes predicted species, scientific name, confidence level, conservation status, DBH or height estimate, and analysis notes.

5. **System Use:** The result is displayed in the AI Tree Scanner and can be used when adding tree records to the inventory.

## Conservation Classification Engine

1. **Purpose:** The conservation engine checks whether the tree belongs to a protected, vulnerable, endangered, or least concern category.

2. **Data Mining Technique:** The system uses Classification to group trees based on conservation category and risk level.

3. **Classification Examples:**

- Least Concern
- Vulnerable
- Endangered
- Protected
- Unknown / Needs Review

4. **Recommendation Output:** If a protected or vulnerable species is detected, the app shows a conservation alert such as "Vulnerable Species - Handle with Care" or a do-not-cut warning.

## Prediction and Estimation Engine

1. **Purpose:** TreeTrace estimates DBH, tree height, carbon value, conservation priority, and monitoring recommendations from collected data.

2. **Data Mining Technique:** The system uses Prediction / Estimation to generate useful values based on image input, DBH records, height records, and field information.

3. **DBH Basis:** DBH stands for Diameter at Breast Height. It is usually measured at 1.3 meters above the ground.

4. **Validation Need:** Predicted DBH is compared with actual manually measured DBH to calculate error values such as MAE and RMSE.

## Descriptive Analytics and Visualization Engine

1. **Purpose:** TreeTrace analyzes stored tree records to show summaries and visual reports.

2. **Data Mining Technique:** The system uses Descriptive Analytics and Data Visualization.

3. **Outputs:**

- Total tree count
- Species count
- GPS-tagged records
- Health summary
- Barangay summary
- Species distribution
- Biodiversity insights
- Conservation alerts
- Carbon stored

4. **Display Screens:** Dashboard, Tree Map, Community Structure, Reports and Tools, Public Tree Profile, and Project Evaluation.

# VI. YOLO-Based DBH and Trunk Detection System

## YOLO Detection Definition

YOLO is used as an object detection technique for identifying visual targets such as the tree trunk and possible reference objects. In TreeTrace, YOLO supports DBH measurement by helping locate the trunk area in an image. This makes the DBH feature more intelligent than a purely manual input field.

## Processing Sequence

1. **Image Acquisition:** The user opens the DBH Measure screen or captures a tree image through the mobile camera.

2. **Guide Alignment:** The user aligns the trunk with the DBH guide, ideally around 1.3 meters from the ground.

3. **Image Submission:** The captured image is sent to the backend DBH analysis endpoint.

4. **YOLO Detection:** If enabled, the backend attempts to detect the trunk and reference object using YOLO.

5. **DBH Estimation:** The system estimates DBH and returns confidence level, method used, height estimate, and analysis notes.

6. **User Confirmation:** The user can use the measurement, restart, or manually validate the result.

## Practical Importance

YOLO improves the DBH workflow by reducing manual guessing and allowing the system to detect image regions related to the trunk. However, the final value should still be treated as an estimate unless verified with a tape measurement.

# VII. AI Image Classification System

## Computer Vision Definition

The AI Tree Scanner performs image classification by processing a tree image and mapping the visual features to possible tree species. The system returns predicted labels, confidence scores, and related botanical or conservation information.

## Processing Sequence

1. **Image Capture or Upload:** The user selects an image from the gallery or captures one using the mobile camera.

2. **Image Preprocessing:** The image is prepared for analysis through resizing, conversion, compression, or backend formatting.

3. **AI Vision Processing:** The backend analyzes the image and attempts to identify the tree species.

4. **Species Output:** The system returns the predicted common name, scientific name, confidence level, and supporting notes.

5. **Conservation Check:** The predicted species is checked against conservation rules or species reference data.

6. **User Review:** The user can confirm, edit, or save the result into the tree inventory.

# VIII. Dataset Used

TreeTrace uses different types of data to support the data mining workflow:

1. **Tree Images:** Used for AI image classification, pattern recognition, and YOLO-supported DBH analysis.

2. **Tree Inventory Records:** Includes common name, scientific name, DBH, height, health status, barangay, GPS coordinates, notes, and image URL.

3. **Conservation Status Records:** Used to classify trees as Least Concern, Vulnerable, Endangered, Protected, or Unknown.

4. **Health Logs:** Used to monitor tree condition, DBH changes, height changes, and field observations.

5. **Evaluation CSV Rows:** Used to compute model evaluation results such as species accuracy, F1-score, conservation accuracy, DBH error, success rate, and latency.

6. **Unknown Species Submissions:** Used for admin review and future improvement of the identification process.

# IX. Mobile Application Features

1. **Login and Registration:** Allows users to securely access the system.

2. **Dashboard:** Shows total trees, health distribution, conservation alerts, reports, and project evaluation access.

3. **AI Tree Scanner:** Provides species prediction, confidence level, conservation status, DBH estimate, and recommendation.

4. **Add Tree:** Saves tree records with species, DBH, height, health, location, image, and notes.

5. **DBH Measure:** Supports tree diameter measurement using camera guide and AI/YOLO-assisted detection.

6. **Tree Map:** Displays tree records using GPS coordinates.

7. **Scan QR:** Opens public tree profiles through QR labels.

8. **Public Tree Profile:** Shows public details such as species, health, DBH, height, carbon, and location.

9. **Community Structure:** Shows biodiversity summaries, species distribution, barangay breakdown, and conservation alerts.

10. **Reports and Tools:** Provides inventory summaries, CSV data, QR labels, route planning, and report support.

11. **Project Evaluation:** Shows project requirements, data mining techniques, insights, deliverables, and model evaluation results.

# X. Model Evaluation Results

The current TreeTrace evaluation uses 26 labeled test rows from the evaluation CSV.

| Test Item | Result | Basis |
|---|---:|---|
| Test Images | 26 | database / CSV evaluation rows |
| Correct Species | 24/26 | actual vs predicted species |
| Species Accuracy | 92.31% | correct species / total images |
| Species F1-score | 0.952 | macro average across tested species |
| Conservation Accuracy | 96.15% | 25/26 correct conservation classifications |
| Measured DBH Set | 26 | trees with manual DBH |
| DBH MAE | +/- 2.12 cm | mean absolute DBH error |
| DBH RMSE | 2.72 cm | root mean squared DBH error |
| Scan Success | 26/26 (100.00%) | completed app scan attempts |
| App Success Rate | 26/26 (100.00%) | successful workflow attempts |
| Average Latency | 2114 ms | average response time |

## Evaluation Interpretation

The results show that TreeTrace can correctly classify most tested tree species and conservation categories. The DBH error values show that the DBH feature can provide useful estimates, but manual measurement is still recommended for official records. The scan success and app success rates show that the app workflow is functional for the tested dataset.

# XI. Expected Deliverables

1. **Project Proposal:** TreeTrace proposal describing the problem, objectives, scope, data mining techniques, and expected system output.

2. **Mobile Application Prototype/System:** A working Flutter mobile app where users can add tree records, scan tree images, measure DBH, view biodiversity insights, and check model evaluation results.

3. **Source Code:** Flutter mobile app, backend API, frontend/admin dashboard, database models, and AI/data mining modules.

4. **Documentation:** System overview, problem statement, objectives, algorithm used, dataset description, screenshots, testing, and model evaluation results.

5. **Dataset Used:** Tree images, tree species records, conservation status data, health logs, DBH records, and evaluation CSV rows.

6. **Final Presentation and Demonstration:** Live demo showing login, dashboard, AI scanning, Add Tree, DBH Measure, Tree Map, Reports and Tools, Community Structure, and Project Evaluation.

# XII. Member Roles

| Role | Assigned Member |
|---|---|
| Project Manager / Documentation Lead | To be assigned |
| UI/UX Designer | To be assigned |
| Mobile Developer | To be assigned |
| Backend Developer | To be assigned |
| Data Mining / Machine Learning Specialist | To be assigned |
| Tester / Quality Assurance | To be assigned |

# XIII. References

[1] Ultralytics, "YOLO Object Detection Documentation." Used as reference for YOLO-based trunk and object detection concepts.

[2] Flutter Documentation, "Flutter Mobile App Development." Used as reference for cross-platform mobile application development.

[3] FastAPI Documentation, "FastAPI Framework." Used as reference for backend API development.

[4] IUCN Red List and Philippine conservation references. Used as conceptual basis for conservation status categories such as Vulnerable, Endangered, and Least Concern.

[5] TreeTrace evaluation CSV and system database records. Used as the project dataset for model evaluation results.
