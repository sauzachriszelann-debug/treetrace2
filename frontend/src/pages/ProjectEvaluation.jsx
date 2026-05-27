import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import api from "@/api/client";
import {
  BarChart3,
  CheckCircle2,
  ClipboardCheck,
  FileText,
  Layers3,
  LineChart,
  Smartphone,
} from "lucide-react";

const deliverables = [
  ["Project Proposal", "TreeTrace proposal and capstone documentation"],
  ["Mobile Application Prototype/System", "Flutter mobile app with AI scan, map, QR scan, DBH, and tree records"],
  ["Source Code", "mobile, backend, and frontend folders"],
  ["Documentation", "capstone documents, diagrams, and system overview"],
  ["Dataset Used", "tree photos, tree records, PlantNet references, protected species data, and trunk model resources"],
  ["Final Presentation and Demonstration", "AI scan, add tree, map, reports, QR, community structure, and evaluation"],
];

const pages = [
  ["Login / Register", "User access and account creation"],
  ["Dashboard", "Summary of tree inventory and system activity"],
  ["AI Tree Scanner", "Species prediction, confidence, DBH/height estimate, and conservation status"],
  ["Add Tree", "Stores tree data, photo, location, DBH, height, and health status"],
  ["DBH Measure", "Manual and AI-assisted DBH measurement"],
  ["Tree Map", "GPS visualization of tree records"],
  ["Scan QR", "Opens public tree profile from a QR tag"],
  ["Public Tree Profile", "Shows tree information, care details, DBH, height, and location"],
  ["Community Structure", "Species distribution, Shannon Index, barangay biodiversity, and endangered list"],
  ["Reports and Tools", "Inventory export, QR labels, route planning, and report validation notes"],
  ["Unknown Species Review", "Expert review for uncertain or low-confidence species"],
  ["Project Evaluation", "Model evaluation results and assignment checklist"],
];

const modelOutputs = [
  ["Species Prediction", "Common name, scientific name, and confidence level"],
  ["Conservation Recommendation", "Protected/endangered status and do-not-cut warning"],
  ["DBH / Height Prediction", "Estimated DBH and height with accuracy notes"],
  ["Biodiversity Insight", "Species count, Shannon Index, top species, and endangered count"],
  ["Map Insight", "Tree locations and barangay distribution"],
  ["Report Insight", "Inventory, carbon estimate, and field validation reminder"],
];

const evaluationRows = [
  ["Number of test images", "30 images", "Prepare labeled tree photos for final testing"],
  ["Correct species predictions", "24 / 30", "Replace with actual group test count"],
  ["Species identification accuracy", "80%", "Correct predictions divided by total images"],
  ["Correct conservation classifications", "28 / 30", "Protected/not protected status check"],
  ["Conservation classification accuracy", "93.33%", "Correct classifications divided by total images"],
  ["Images with measured DBH", "10 images", "Use trees with field-measured DBH"],
  ["Average DBH error", "+/- 10 to 30 cm", "Compare predicted DBH against measured DBH"],
  ["Successful app scan attempts", "30 / 30", "Checks if scanning completes without app failure"],
  ["App scan success rate", "100%", "Successful scans divided by total attempts"],
];

const fetchEvaluationResults = async () => {
  const { data } = await api.get("/evaluation/results");
  return data;
};

const importEvaluationCsv = async () => {
  const { data } = await api.post("/evaluation/import-csv", null, {
    params: { replace: true },
  });
  return data;
};

const evaluationMethods = [
  ["Species Classification Accuracy", "Correct species predictions / total labeled test images"],
  ["Conservation Classification Accuracy", "Correct protected, endangered, vulnerable, or not-listed classifications / total test images"],
  ["DBH Measurement Error", "Compare AI/YOLO-assisted DBH estimate against manual tape measurement"],
  ["Scan Success Rate", "Successful image scans / total image scan attempts"],
  ["App Success Rate", "Successful mobile workflow: scan, measure DBH, save tree, view reports, and show evaluation"],
];

const techniques = [
  ["Image Classification", "Identifies possible tree species from photos"],
  ["Pattern Recognition", "Analyzes leaves, bark, trunk shape, flowers, and fruit"],
  ["Classification", "Groups species by conservation status"],
  ["Prediction / Estimation", "Estimates DBH, height, and tree attributes"],
  ["Descriptive Analytics", "Summarizes species, barangays, and biodiversity"],
  ["Data Visualization", "Shows charts, maps, and reports"],
];

export default function ProjectEvaluation() {
  const queryClient = useQueryClient();
  const { data: generatedEvaluation, isLoading } = useQuery({
    queryKey: ["evaluation-results"],
    queryFn: fetchEvaluationResults,
    retry: false,
  });
  const importMutation = useMutation({
    mutationFn: importEvaluationCsv,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["evaluation-results"] }),
  });
  const rows = generatedEvaluation?.metrics?.length
    ? generatedEvaluation.metrics.map((item) => [item.label, item.value, item.note])
    : evaluationRows;
  const isDatabase = generatedEvaluation?.source === "database";
  const isGenerated = generatedEvaluation?.source === "generated_file" || generatedEvaluation?.source === "generated";

  return (
    <div className="p-8 space-y-6">
      <div>
        <h1 className="font-fraunces text-3xl font-semibold">Project Evaluation</h1>
        <p className="text-muted-foreground mt-1">
          Data mining assignment checklist, app pages, model outputs, and evaluation results.
        </p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <MetricCard icon={Smartphone} label="Prototype" value="Mobile App" />
        <MetricCard icon={Layers3} label="Technique" value="Image Classification" />
        <MetricCard icon={BarChart3} label="Evaluation" value="Accuracy + DBH Error" />
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <FileText className="w-5 h-5" />
            Expected Deliverables
          </CardTitle>
        </CardHeader>
        <CardContent>
          <DataTable headers={["Deliverable", "TreeTrace Evidence"]} rows={deliverables} />
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Smartphone className="w-5 h-5" />
            Pages Needed for the Assignment
          </CardTitle>
        </CardHeader>
        <CardContent>
          <DataTable headers={["Page / Screen", "Purpose"]} rows={pages} />
        </CardContent>
      </Card>

      <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <LineChart className="w-5 h-5" />
              Data Mining Techniques
            </CardTitle>
          </CardHeader>
          <CardContent>
            <DataTable headers={["Technique", "Use in TreeTrace"]} rows={techniques} />
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <CheckCircle2 className="w-5 h-5" />
              Meaningful Outputs
            </CardTitle>
          </CardHeader>
          <CardContent>
            <DataTable headers={["Output", "What the User Sees"]} rows={modelOutputs} />
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <ClipboardCheck className="w-5 h-5" />
            Model Evaluation Used
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <p className="text-sm text-muted-foreground leading-relaxed">
            TreeTrace evaluates the actual app features: species classification, conservation classification,
            DBH measurement error, scan success, and app workflow success. Do not claim mAP, F1-score,
            confusion matrix, or CNN training results unless the group has actually tested and recorded them.
          </p>
          <DataTable headers={["Metric", "How to Measure It"]} rows={evaluationMethods} />
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <div className="flex items-center justify-between gap-4">
            <CardTitle className="flex items-center gap-2">
              <ClipboardCheck className="w-5 h-5" />
              Model Evaluation Results
            </CardTitle>
            <Badge variant="secondary">Defense-ready table</Badge>
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          <p className="text-sm text-muted-foreground leading-relaxed">
            Use this table for the final presentation. The sample values show the required format;
            replace them with the group&apos;s actual test results after scanning labeled tree images.
          </p>
          <div className="rounded-lg border bg-muted/40 p-3 text-sm text-muted-foreground">
            {isLoading
              ? "Loading generated evaluation results..."
              : isDatabase
                ? "Showing evaluation results calculated from database rows."
                : isGenerated
                  ? "Showing generated results from capstone/evaluation_outputs."
                  : "Showing sample values. Import the CSV to store test rows in the database."}
          </div>
          <Button
            type="button"
            variant="outline"
            onClick={() => importMutation.mutate()}
            disabled={importMutation.isPending}
          >
            {importMutation.isPending ? "Importing..." : "Import CSV to Database"}
          </Button>
          <DataTable headers={["Test Item", "Result", "Basis"]} rows={rows} />
        </CardContent>
      </Card>
    </div>
  );
}

function MetricCard({ icon: Icon, label, value }) {
  return (
    <Card>
      <CardContent className="p-4 flex items-center gap-3">
        <div className="w-10 h-10 rounded-lg bg-muted flex items-center justify-center">
          <Icon className="w-5 h-5 text-primary" />
        </div>
        <div>
          <p className="text-xs text-muted-foreground">{label}</p>
          <p className="font-fraunces text-xl font-semibold">{value}</p>
        </div>
      </CardContent>
    </Card>
  );
}

function DataTable({ headers, rows }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-border text-muted-foreground text-xs">
            {headers.map((header) => (
              <th key={header} className="text-left py-2 pr-4 font-medium">
                {header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row.join("-")} className="border-b border-border/50">
              {row.map((cell, index) => (
                <td
                  key={`${cell}-${index}`}
                  className={index === 0 ? "py-3 pr-4 font-medium" : "py-3 pr-4 text-muted-foreground"}
                >
                  {cell}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
