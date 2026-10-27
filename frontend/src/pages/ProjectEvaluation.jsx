import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { evaluationApi } from "@/api/evaluation";
import { useAuth } from "@/lib/AuthContext";
import {
  AlertTriangle,
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
  ["Dataset Used", "Tree photos, tree records, PlantNet references, protected species data, and the frozen evaluation manifest"],
  ["Final Presentation and Demonstration", "AI scan, add tree, map, reports, QR, community structure, and evaluation"],
];

const pages = [
  ["Login / Register", "User access and account creation"],
  ["Dashboard", "Summary of tree inventory and system activity"],
  ["AI Tree Scanner", "Species prediction, confidence level, DBH/height estimate, and conservation status"],
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

const evaluationMethods = [
  ["Species Classification Accuracy", "Correct species predictions / scoreable labeled test images, reported with a Wilson 95% confidence interval and the sample count n"],
  ["Coverage", "Scoreable images / total test images; abstentions (not identified) are reported, never silently dropped"],
  ["Precision / Recall / F1 (per class)", "TP/(TP+FP), TP/(TP+FN), 2PR/(P+R) for every class in the test set, with support counts"],
  ["Macro F1 / Weighted F1", "Unweighted mean of per-class F1 / support-weighted mean of per-class F1"],
  ["Confusion Matrix", "Rows = true class, columns = predicted class, raw counts over scoreable images"],
  ["Conservation Classification Accuracy", "Correct protected/endangered/vulnerable/not-listed classifications / test images with both labels"],
  ["DBH Measurement Error", "MAE, RMSE, and bias of AI/YOLO-assisted DBH against manual tape measurement (cm), with n"],
  ["Confidence Reliability", "Empirical accuracy within each reported-confidence bucket; confidence is a model self-report, not an accuracy claim"],
  ["Scan / App Success Rate", "Field-captured workflow indicators (unverified provenance) - never part of official model metrics"],
];

const techniques = [
  ["Image Classification", "Identifies possible tree species from photos"],
  ["Pattern Recognition", "Analyzes leaves, bark, trunk shape, flowers, and fruit"],
  ["Classification", "Groups species by conservation status"],
  ["Prediction / Estimation", "Estimates DBH, height, and tree attributes"],
  ["Descriptive Analytics", "Summarizes species, barangays, and biodiversity"],
  ["Data Visualization", "Shows charts, maps, and reports"],
];

const NOT_EVALUATED_TITLE = "Not yet evaluated";

function fmtPercent(value) {
  if (value === null || value === undefined) return "Not evaluated";
  return `${(value * 100).toFixed(2)}%`;
}

function fmtNumber(value, digits = 3) {
  if (value === null || value === undefined) return "Not evaluated";
  return Number(value).toFixed(digits);
}

function shortHash(value) {
  if (!value) return "—";
  return value.length > 12 ? `${value.slice(0, 12)}…` : value;
}

function fmtInt(value) {
  return value === null || value === undefined ? "—" : String(value);
}

export default function ProjectEvaluation() {
  const queryClient = useQueryClient();
  const { user } = useAuth();
  const role = String(user?.role || "");
  const isAdmin =
    role === "admin" || role.includes("UserRole.admin") || role.endsWith(".admin");
  const isStaff =
    isAdmin ||
    role === "field_worker" ||
    role.includes("field_worker") ||
    role.endsWith(".field_worker");

  const {
    data: results,
    isLoading,
    isError,
    error,
  } = useQuery({
    queryKey: ["evaluation-results"],
    queryFn: evaluationApi.results,
    retry: false,
  });

  const { data: fieldRows } = useQuery({
    queryKey: ["evaluation-field-rows"],
    queryFn: evaluationApi.listFieldRows,
    enabled: isStaff,
    retry: false,
  });

  const importMutation = useMutation({
    mutationFn: () => evaluationApi.importFieldCsv(true),
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: ["evaluation-field-rows"] }),
  });

  const state = isLoading
    ? "loading"
    : isError
      ? "error"
      : results?.state || "unknown";
  const run = results?.run;
  const species = run?.metrics?.species;
  const conservation = run?.metrics?.conservation;
  const dbh = run?.metrics?.dbh;
  const latency = run?.metrics?.latency_ms;
  const reliability = run?.metrics?.confidence_reliability;
  const confusion = run?.confusion_matrix;

  return (
    <div className="p-8 space-y-6">
      <div>
        <h1 className="font-fraunces text-3xl font-semibold">Project Evaluation</h1>
        <p className="text-muted-foreground mt-1">
          Data mining assignment checklist, app pages, model outputs, and
          artifact-based evaluation results.
        </p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <MetricCard icon={Smartphone} label="Prototype" value="Mobile App" />
        <MetricCard icon={Layers3} label="Technique" value="Image Classification" />
        <MetricCard
          icon={BarChart3}
          label="Evaluation"
          value={
            state === "evaluated"
              ? `Recorded run (n=${fmtInt(species?.n_total)})`
              : state === "invalid_artifact"
                ? "Artifact failed validation"
                : NOT_EVALUATED_TITLE
          }
        />
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
            Model Evaluation Method
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <p className="text-sm text-muted-foreground leading-relaxed">
            Metrics are computed only by the offline runner from a frozen,
            independently labeled test manifest, and are served only from
            validated, versioned artifacts. Every metric is reported with its
            sample count and provenance. Confidence is the model&apos;s
            self-reported score and is never presented as accuracy. Field rows
            have unverified provenance and never feed official metrics.
          </p>
          <DataTable headers={["Metric", "How It Is Measured"]} rows={evaluationMethods} />
        </CardContent>
      </Card>

      {/* ── Official evaluation results (artifact-backed, state-based) ── */}
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between gap-4">
            <CardTitle className="flex items-center gap-2">
              <ClipboardCheck className="w-5 h-5" />
              Model Evaluation Results
            </CardTitle>
            {state === "evaluated" && (
              <Badge variant="secondary">Committed evaluation run</Badge>
            )}
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          {state === "loading" && (
            <p className="text-sm text-muted-foreground">
              Loading evaluation results...
            </p>
          )}

          {state === "error" && (
            <div className="rounded-lg border border-amber-500/40 bg-amber-500/10 p-4 text-sm">
              <p className="font-medium flex items-center gap-2">
                <AlertTriangle className="w-4 h-4" />
                Could not load evaluation results.
              </p>
              <p className="text-muted-foreground mt-1">
                {error?.message || "The evaluation API is unavailable."} No
                numbers are shown when results cannot be loaded.
              </p>
            </div>
          )}

          {state === "not_evaluated" && (
            <div className="rounded-lg border bg-muted/40 p-4 space-y-2 text-sm">
              <p className="font-semibold">{NOT_EVALUATED_TITLE}</p>
              <p className="text-muted-foreground leading-relaxed">
                {results?.reason ||
                  "No committed evaluation run exists yet."}
              </p>
              <p className="text-muted-foreground leading-relaxed">
                A run is produced by{" "}
                <code className="text-xs">backend/scripts/evaluate_species.py</code>{" "}
                over the frozen test manifest and appears here only after it is
                validated and committed. Placeholder numbers are never shown.
              </p>
            </div>
          )}

          {state === "invalid_artifact" && (
            <div className="rounded-lg border border-red-500/40 bg-red-500/10 p-4 space-y-2 text-sm">
              <p className="font-medium flex items-center gap-2">
                <AlertTriangle className="w-4 h-4" />
                The newest evaluation artifact failed validation.
              </p>
              <p className="text-muted-foreground">
                {results?.reason} No metrics are shown instead of falling back
                to older numbers.
              </p>
              <ul className="list-disc pl-5 text-muted-foreground space-y-1">
                {(results?.issues || []).map((issue) => (
                  <li key={issue}>{issue}</li>
                ))}
              </ul>
            </div>
          )}

          {(state === "evaluated" || state === "unavailable") && run && (
            <div className="space-y-6">
              {/* Provenance */}
              <div className="rounded-lg border bg-muted/40 p-3 text-xs text-muted-foreground grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-1">
                <span>Run: <code>{run.run_id}</code></span>
                <span>Pipeline: {run.model?.pipeline}</span>
                <span>Dataset: {run.dataset?.name}</span>
                <span>Manifest: {shortHash(run.dataset?.manifest_sha256)}</span>
                <span>Commit: {shortHash(run.environment?.git_commit)}</span>
                <span>
                  Finished: {run.environment?.finished_at || "—"}
                </span>
                <span>
                  External API calls:{" "}
                  {run.environment?.external_api_calls ? "yes" : "no"}
                </span>
                <span>
                  Local TFLite model present:{" "}
                  {run.model?.local_tflite_present ? "yes" : "no"}
                </span>
              </div>

              {run.state !== "evaluated" && (
                <div className="rounded-lg border bg-muted/40 p-3 text-sm text-muted-foreground">
                  This run is marked <strong>{run.state}</strong>: no metrics
                  are displayed for it.
                </div>
              )}

              {run.state === "evaluated" && (
                <>
                  <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                    <MetricCard
                      icon={BarChart3}
                      label={`Species accuracy (n=${fmtInt(species?.n_scoreable)})`}
                      value={
                        species?.accuracy === null ||
                        species?.accuracy === undefined
                          ? "No scoreable samples"
                          : `${fmtPercent(species.accuracy)} ± ${fmtPercent(
                              (species?.accuracy_ci95?.[1] ?? 0) -
                                (species?.accuracy ?? 0),
                            )} (95% CI)`
                      }
                      sub={`coverage ${fmtPercent(species?.coverage)} of ${
                        fmtInt(species?.n_total)
                      } images`}
                    />
                    <MetricCard
                      icon={LineChart}
                      label="F1 (per-class averages)"
                      value={`macro ${fmtNumber(species?.macro_f1)} / weighted ${fmtNumber(
                        species?.weighted_f1,
                      )}`}
                      sub={`${fmtInt(species?.n_classes)} classes, ${
                        species?.n_low_support ?? 0
                      } low-support (<${species?.low_support_threshold ?? 5})`}
                    />
                    <MetricCard
                      icon={CheckCircle2}
                      label={`Conservation accuracy (n=${fmtInt(
                        conservation?.n_scoreable,
                      )})`}
                      value={fmtPercent(conservation?.accuracy)}
                      sub={
                        conservation?.accuracy_ci95
                          ? `95% CI ${fmtPercent(conservation.accuracy_ci95[0])}–${fmtPercent(
                              conservation.accuracy_ci95[1],
                            )}`
                          : "no labeled conservation pairs"
                      }
                    />
                    <MetricCard
                      icon={Smartphone}
                      label={`DBH error (n=${fmtInt(dbh?.n)})`}
                      value={
                        dbh?.n
                          ? `MAE ${fmtNumber(dbh.mae_cm, 2)} cm`
                          : "No measured DBH in run"
                      }
                      sub={
                        dbh?.n
                          ? `RMSE ${fmtNumber(dbh.rmse_cm, 2)} cm · bias ${fmtNumber(
                              dbh.bias_cm,
                              2,
                            )} cm (${dbh.pipeline || "pipeline n/a"})`
                          : "MAE/RMSE not defined for n=0"
                      }
                    />
                    <MetricCard
                      icon={Layers3}
                      label={`Latency (n=${fmtInt(latency?.n)})`}
                      value={latency?.n ? `p50 ${fmtInt(Math.round(latency.p50_ms))} ms` : "No latency samples"}
                      sub={
                        latency?.n
                          ? `mean ${fmtInt(Math.round(latency.mean_ms))} ms · p95 ${fmtInt(
                              Math.round(latency.p95_ms),
                            )} ms`
                          : "—"
                      }
                    />
                    <MetricCard
                      icon={AlertTriangle}
                      label="Abstentions"
                      value={`${fmtInt(species?.n_no_prediction)} / ${fmtInt(
                        species?.n_total,
                      )}`}
                      sub={
                        species?.n_no_prediction
                          ? "excluded from accuracy; shown via coverage"
                          : "every image received a prediction"
                      }
                    />
                  </div>

                  <p className="text-xs text-muted-foreground leading-relaxed rounded-lg border bg-muted/40 p-3">
                    {reliability?.note}
                  </p>

                  {/* Confidence reliability */}
                  <div>
                    <h3 className="text-sm font-semibold mb-2">
                      Confidence reliability (reported confidence vs measured
                      accuracy)
                    </h3>
                    <DataTable
                      headers={[
                        "Reported confidence",
                        "Images (n)",
                        "Mean reported score",
                        "Empirical accuracy",
                      ]}
                      rows={(reliability?.buckets || []).map((bucket) => [
                        bucket.bucket,
                        String(bucket.n),
                        bucket.mean_reported_confidence === null
                          ? "not reported"
                          : fmtNumber(bucket.mean_reported_confidence, 3),
                        bucket.empirical_accuracy === null
                          ? "no scoreable samples"
                          : fmtPercent(bucket.empirical_accuracy),
                      ])}
                    />
                  </div>

                  {/* Per-class metrics */}
                  <div>
                    <h3 className="text-sm font-semibold mb-2">
                      Per-class metrics
                    </h3>
                    <div className="overflow-x-auto">
                      <table className="w-full text-sm">
                        <thead>
                          <tr className="border-b border-border text-muted-foreground text-xs">
                            <th className="text-left py-2 pr-4 font-medium">Class</th>
                            <th className="text-right py-2 pr-4 font-medium">Support</th>
                            <th className="text-right py-2 pr-4 font-medium">Predicted</th>
                            <th className="text-right py-2 pr-4 font-medium">Precision</th>
                            <th className="text-right py-2 pr-4 font-medium">Recall</th>
                            <th className="text-right py-2 pr-4 font-medium">F1</th>
                          </tr>
                        </thead>
                        <tbody>
                          {(species?.per_class || []).map((entry) => (
                            <tr
                              key={entry.class}
                              className="border-b border-border/50"
                            >
                              <td className="py-2 pr-4 font-medium">
                                {entry.class}
                                {entry.low_support && (
                                  <Badge
                                    variant="outline"
                                    className="ml-2 text-[10px]"
                                  >
                                    low support
                                  </Badge>
                                )}
                              </td>
                              <td className="py-2 pr-4 text-right">
                                {entry.support}
                              </td>
                              <td className="py-2 pr-4 text-right">
                                {entry.predicted}
                              </td>
                              <td className="py-2 pr-4 text-right">
                                {fmtNumber(entry.precision)}
                              </td>
                              <td className="py-2 pr-4 text-right">
                                {fmtNumber(entry.recall)}
                              </td>
                              <td className="py-2 pr-4 text-right">
                                {fmtNumber(entry.f1)}
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  </div>

                  {/* Confusion matrix */}
                  <div>
                    <h3 className="text-sm font-semibold mb-2">
                      Confusion matrix (rows = true, columns = predicted)
                    </h3>
                    {confusion?.labels?.length ? (
                      <div className="overflow-x-auto">
                        <table className="w-full text-xs">
                          <thead>
                            <tr className="border-b border-border text-muted-foreground">
                              <th className="text-left py-2 pr-3 font-medium">
                                true \ predicted
                              </th>
                              {confusion.labels.map((label) => (
                                <th
                                  key={label}
                                  className="text-right py-2 px-2 font-medium"
                                >
                                  {label}
                                </th>
                              ))}
                            </tr>
                          </thead>
                          <tbody>
                            {confusion.labels.map((label, rowIndex) => (
                              <tr
                                key={label}
                                className="border-b border-border/50"
                              >
                                <td className="py-2 pr-3 font-medium whitespace-nowrap">
                                  {label}
                                </td>
                                {(confusion.counts[rowIndex] || []).map(
                                  (count, colIndex) => (
                                    <td
                                      key={`${label}-${colIndex}`}
                                      className={`py-2 px-2 text-right ${
                                        rowIndex === colIndex && count > 0
                                          ? "text-emerald-500 font-semibold"
                                          : count > 0
                                            ? "text-red-400"
                                            : "text-muted-foreground"
                                      }`}
                                    >
                                      {count}
                                    </td>
                                  ),
                                )}
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    ) : (
                      <p className="text-sm text-muted-foreground">
                        No scoreable samples - no confusion matrix exists for
                        this run.
                      </p>
                    )}
                  </div>
                </>
              )}
            </div>
          )}
        </CardContent>
      </Card>

      {/* ── Field-captured rows (staff only; never official metrics) ── */}
      {isStaff && (
        <Card>
          <CardHeader>
            <div className="flex items-center justify-between gap-4">
              <CardTitle className="flex items-center gap-2">
                <ClipboardCheck className="w-5 h-5" />
                Field-Captured Rows
                <Badge variant="outline">unverified</Badge>
              </CardTitle>
              {isAdmin && (
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() => importMutation.mutate()}
                  disabled={importMutation.isPending}
                >
                  {importMutation.isPending ? "Importing..." : "Import CSV to Database"}
                </Button>
              )}
            </div>
          </CardHeader>
          <CardContent className="space-y-4">
            <p className="text-sm text-muted-foreground leading-relaxed">
              {results?.field_rows?.note ||
                "Field-captured rows have unverified provenance and never contribute to official metrics."}
            </p>
            <p className="text-xs text-muted-foreground">
              Rows: {fmtInt(results?.field_rows?.count ?? 0)} · included in
              official metrics:{" "}
              <strong>
                {results?.field_rows?.included_in_official_metrics
                  ? "yes"
                  : "no"}
              </strong>
            </p>
            {fieldRows?.length ? (
              <DataTable
                headers={[
                  "Image",
                  "Actual species",
                  "Predicted species",
                  "Actual DBH",
                  "Predicted DBH",
                  "Scan OK",
                ]}
                rows={fieldRows.slice(0, 50).map((row) => [
                  row.image_id,
                  row.actual_species || "—",
                  row.predicted_species || "— (no prediction)",
                  row.actual_dbh_cm === null ? "—" : String(row.actual_dbh_cm),
                  row.predicted_dbh_cm === null
                    ? "— (no prediction)"
                    : String(row.predicted_dbh_cm),
                  row.app_success ? "yes" : "no",
                ])}
              />
            ) : (
              <p className="text-sm text-muted-foreground">
                No field-captured rows recorded.
              </p>
            )}
            {fieldRows?.length > 50 && (
              <p className="text-xs text-muted-foreground">
                Showing the 50 most recent of {fieldRows.length} rows.
              </p>
            )}
          </CardContent>
        </Card>
      )}
    </div>
  );
}

function MetricCard({ icon: Icon, label, value, sub }) {
  return (
    <Card>
      <CardContent className="p-4 space-y-1">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-lg bg-muted flex items-center justify-center shrink-0">
            <Icon className="w-5 h-5 text-primary" />
          </div>
          <div className="min-w-0">
            <p className="text-xs text-muted-foreground truncate">{label}</p>
            <p className="font-fraunces text-lg font-semibold truncate">{value}</p>
          </div>
        </div>
        {sub && <p className="text-xs text-muted-foreground">{sub}</p>}
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
                  className={
                    index === 0
                      ? "py-3 pr-4 font-medium"
                      : "py-3 pr-4 text-muted-foreground"
                  }
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
