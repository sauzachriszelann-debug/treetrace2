import { useNavigate, useParams } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { publicApiService } from "@/api/publicApi";
import HealthBadge from "@/components/trees/HealthBadge";
import { useState, useEffect } from "react";
import { format } from "date-fns";
import {
  MapPin, Ruler, Leaf, Calendar, TreePine, Droplets,
  Sun, Thermometer, Wind, Shield, BookOpen, Star,
  HelpCircle, AlertTriangle, Sprout, History, ChevronDown, ChevronUp,
  ArrowLeft
} from "lucide-react";

// ── AI Wiki Content Generator ─────────────────────────────────────────────────
async function fetchTreeWiki(treeId) {
  const res = await fetch(`/api/public/tree/${treeId}/wiki`);
  if (!res.ok) throw new Error("Wiki fetch failed");
  return res.json();
}

// ── Sub-components ─────────────────────────────────────────────────────────────
function Section({ icon: Icon, title, children, defaultOpen = true }) {
  const [open, setOpen] = useState(defaultOpen);
  return (
    <div className="border-b border-[#e8ede6] last:border-0">
      <button
        onClick={() => setOpen(!open)}
        className="w-full flex items-center justify-between py-4 px-5 text-left"
      >
        <div className="flex items-center gap-2.5">
          {Icon && <Icon className="w-4 h-4 text-[#2d6a4f]" />}
          <span className="font-semibold text-[#1a2e1a] text-sm">{title}</span>
        </div>
        {open ? <ChevronUp className="w-4 h-4 text-[#6b8f71]" /> : <ChevronDown className="w-4 h-4 text-[#6b8f71]" />}
      </button>
      {open && <div className="px-5 pb-5">{children}</div>}
    </div>
  );
}

function ScoreBar({ label, score }) {
  const pct = Math.min(5, Math.max(0, parseInt(score) || 3));
  return (
    <div className="flex items-center gap-3">
      <span className="text-xs text-[#6b8f71] w-16 flex-shrink-0">{label}</span>
      <div className="flex gap-1">
        {[1,2,3,4,5].map(i => (
          <div key={i} className={`w-5 h-2 rounded-full ${i <= pct ? "bg-[#2d6a4f]" : "bg-[#e8ede6]"}`} />
        ))}
      </div>
    </div>
  );
}

function InfoRow({ label, value }) {
  if (!value) return null;
  return (
    <div className="flex flex-col gap-1 py-2 border-b border-[#f0f4ef] last:border-0 sm:flex-row sm:justify-between sm:items-start">
      <span className="text-xs text-[#6b8f71] flex-shrink-0 sm:w-32">{label}</span>
      <span className="text-xs text-[#1a2e1a] font-medium sm:text-right break-words">{value}</span>
    </div>
  );
}

function CareChip({ icon: Icon, label, value, color }) {
  return (
    <div className={`flex items-center gap-2 px-3 py-2 rounded-xl ${color} flex-1 min-w-0`}>
      <Icon className="w-4 h-4 flex-shrink-0" />
      <div className="min-w-0">
        <p className="text-[10px] opacity-70 leading-none">{label}</p>
        <p className="text-xs font-semibold truncate mt-0.5">{value}</p>
      </div>
    </div>
  );
}

function FAQItem({ q, a }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="border border-[#e8ede6] rounded-xl overflow-hidden mb-2">
      <button
        onClick={() => setOpen(!open)}
        className="w-full flex items-center justify-between p-3 text-left bg-[#f8faf7]"
      >
        <span className="text-xs font-medium text-[#1a2e1a] pr-2">{q}</span>
        {open ? <ChevronUp className="w-3.5 h-3.5 text-[#6b8f71] flex-shrink-0" /> : <ChevronDown className="w-3.5 h-3.5 text-[#6b8f71] flex-shrink-0" />}
      </button>
      {open && <div className="p-3 text-xs text-[#4a6741] leading-relaxed bg-white">{a}</div>}
    </div>
  );
}

// ── Main Page ──────────────────────────────────────────────────────────────────
export default function PublicTreeProfile() {
  const { id } = useParams();
  const navigate = useNavigate();
  const [wiki, setWiki]     = useState(null);
  const [wikiLoading, setWikiLoading] = useState(false);
  const [wikiError, setWikiError]     = useState(false);
  const [activeTab, setActiveTab]     = useState("overview");

  const { data: tree, isLoading, isError } = useQuery({
    queryKey: ["public-tree", id],
    queryFn: () => publicApiService.getTree(id),
  });

  const { data: logs = [] } = useQuery({
    queryKey: ["public-tree-logs", id],
    queryFn: () => publicApiService.getTreeHealthLogs(id),
    enabled: !!tree,
  });

  useEffect(() => {
    if (!tree) return;
    setWikiLoading(true);
    setWikiError(false);
    fetchTreeWiki(tree.id)
      .then(setWiki)
      .catch(() => setWikiError(true))
      .finally(() => setWikiLoading(false));
  }, [tree?.id]);

  if (isLoading) return (
    <div className="min-h-screen bg-[#f4f7f3] flex items-center justify-center">
      <div className="flex flex-col items-center gap-3">
        <div className="w-10 h-10 border-3 border-[#2d6a4f]/20 border-t-[#2d6a4f] rounded-full animate-spin" />
        <p className="text-sm text-[#6b8f71]">Loading tree profile…</p>
      </div>
    </div>
  );

  if (isError || !tree) return (
    <div className="min-h-screen bg-[#f4f7f3] flex items-center justify-center px-4">
      <div className="text-center">
        <TreePine className="w-16 h-16 mx-auto mb-4 text-[#6b8f71]/30" />
        <h2 className="text-xl font-bold text-[#1a2e1a] mb-2">Tree Not Found</h2>
        <p className="text-sm text-[#6b8f71]">This QR code may be invalid or the tree has been removed.</p>
      </div>
    </div>
  );

  const tabs = ["overview", "care", "info", "history"];

  return (
    <div className="min-h-screen bg-[#f4f7f3]">

      {/* ── Hero ── */}
      <div className="px-0 pt-0 sm:px-4 sm:pt-4">
      <div className="relative h-[340px] overflow-hidden sm:mx-auto sm:h-[420px] sm:max-w-5xl sm:rounded-3xl sm:border sm:border-[#dfe8dc] sm:shadow-sm">
        {tree.photo_url ? (
          <img src={tree.photo_url} alt={tree.common_name} className="w-full h-full object-cover object-center" />
        ) : (
          <div className="w-full h-full bg-gradient-to-br from-[#2d6a4f] to-[#52b788] flex items-center justify-center">
            <TreePine className="w-28 h-28 text-white/20" />
          </div>
        )}
        {/* Gradient overlay */}
        <div className="absolute inset-0 bg-gradient-to-t from-black/75 via-black/25 to-black/10" />

        <button
          onClick={() => (window.history.length > 1 ? navigate(-1) : navigate("/public"))}
          className="absolute top-4 left-4 flex h-10 w-10 items-center justify-center rounded-full border border-white/30 bg-black/25 text-white backdrop-blur-md transition hover:bg-black/40"
          aria-label="Back"
        >
          <ArrowLeft className="h-5 w-5" />
        </button>

        {/* Brand badge */}
        <div className="absolute top-4 left-16 flex items-center gap-1.5 bg-white/20 backdrop-blur-md px-3 py-2 rounded-full border border-white/30">
          <Leaf className="w-3.5 h-3.5 text-white" />
          <span className="text-white text-xs font-semibold tracking-wide">TreeTrace</span>
        </div>

        {/* Health badge */}
        <div className="absolute top-4 right-4 max-w-[48vw] sm:max-w-none">
          <div className={`px-3 py-2 rounded-full text-[11px] font-bold shadow-sm sm:text-xs ${
            tree.health_status === "Healthy" ? "bg-emerald-500 text-white" :
            tree.health_status === "Fair"    ? "bg-amber-500 text-white" :
            "bg-red-500 text-white"
          }`}>
            {tree.health_status === "Healthy" ? "✓ This plant looks Healthy!" :
             tree.health_status === "Fair"    ? "⚠ Fair condition" : "⚠ Poor condition"}
          </div>
        </div>

        {/* Tree name overlay */}
        <div className="absolute bottom-0 left-0 right-0 p-5 sm:p-8">
          <h1 className="text-white text-3xl font-bold leading-tight sm:text-5xl">{tree.common_name}</h1>
          {tree.scientific_name && (
            <p className="text-white/80 text-sm italic mt-1 sm:text-base">Also known as {tree.scientific_name}</p>
          )}
          {wiki?.tagline && !wikiLoading && (
            <p className="text-white/70 text-xs mt-2 max-w-3xl leading-relaxed sm:text-sm">{wiki.tagline}</p>
          )}
        </div>
      </div>
      </div>

      {/* ── Quick stats strip ── */}
      <div className="bg-white border-b border-[#e8ede6] px-4 py-3">
        <div className="max-w-5xl mx-auto flex gap-4 overflow-x-auto px-1 sm:justify-center">
          {tree.barangay && (
            <div className="flex items-center gap-1.5 text-xs text-[#6b8f71] flex-shrink-0">
              <MapPin className="w-3.5 h-3.5" />
              <span>{tree.barangay}</span>
            </div>
          )}
          {tree.dbh_cm && (
            <div className="flex items-center gap-1.5 text-xs text-[#6b8f71] flex-shrink-0">
              <Ruler className="w-3.5 h-3.5" />
              <span>DBH {tree.dbh_cm} cm</span>
            </div>
          )}
          {tree.carbon_kg && (
            <div className="flex items-center gap-1.5 text-xs text-[#6b8f71] flex-shrink-0">
              <Leaf className="w-3.5 h-3.5" />
              <span>{tree.carbon_kg.toFixed(1)} kg CO₂</span>
            </div>
          )}
          {tree.date_recorded && (
            <div className="flex items-center gap-1.5 text-xs text-[#6b8f71] flex-shrink-0">
              <Calendar className="w-3.5 h-3.5" />
              <span>{format(new Date(tree.date_recorded), "MMM d, yyyy")}</span>
            </div>
          )}
        </div>
      </div>

      {/* ── Tab nav ── */}
      <div className="bg-white border-b border-[#e8ede6] sticky top-0 z-10">
        <div className="max-w-5xl mx-auto flex">
          {tabs.map(tab => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              className={`flex-1 py-3 text-xs font-semibold capitalize transition-colors border-b-2 ${
                activeTab === tab
                  ? "border-[#2d6a4f] text-[#2d6a4f]"
                  : "border-transparent text-[#6b8f71]"
              }`}
            >
              {tab}
            </button>
          ))}
        </div>
      </div>

      {/* ── Content ── */}
      <div className="max-w-2xl mx-auto pb-16">

        {/* ── Save to Garden CTA ── */}
        <div className="mx-4 mt-4 bg-[#2d6a4f] text-white rounded-2xl px-4 py-3 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Sprout className="w-5 h-5" />
            <div>
              <p className="text-xs font-semibold">Scan to identify trees near you</p>
              <p className="text-[10px] opacity-70">Powered by TreeTrace · Panabo City</p>
            </div>
          </div>
          <div className="bg-white/20 px-3 py-1.5 rounded-lg text-xs font-bold">Explore</div>
        </div>

        {/* ── Wiki loading skeleton ── */}
        {wikiLoading && (
          <div className="mx-4 mt-4 bg-white rounded-2xl p-5 border border-[#e8ede6]">
            <div className="flex items-center gap-2 mb-3">
              <div className="w-4 h-4 border-2 border-[#2d6a4f]/20 border-t-[#2d6a4f] rounded-full animate-spin" />
              <span className="text-xs text-[#6b8f71]">Loading species encyclopedia…</span>
            </div>
            {[1,2,3].map(i => (
              <div key={i} className="h-3 bg-[#f0f4ef] rounded animate-pulse mb-2" style={{ width: `${70 + i*10}%` }} />
            ))}
          </div>
        )}

        {wikiError && (
          <div className="mx-4 mt-4 bg-amber-50 border border-amber-200 rounded-2xl p-4 text-xs text-amber-700">
            Could not load species encyclopedia. Showing basic tree data only.
          </div>
        )}

        {/* ══ OVERVIEW TAB ══ */}
        {activeTab === "overview" && wiki && !wikiLoading && (
          <div className="mt-4 space-y-3">

            {/* Basic Info */}
            <div className="mx-4 bg-white rounded-2xl overflow-hidden border border-[#e8ede6]">
              <Section icon={Leaf} title="Basic Info">
                <InfoRow label="Native to" value={wiki.basic_info?.native_to} />
                <InfoRow label="Invasive Status" value={wiki.basic_info?.invasive_status} />
                <InfoRow label="Plant Type" value={wiki.basic_info?.plant_type} />
                <InfoRow label="Lifespan" value={wiki.basic_info?.lifespan} />
                <InfoRow label="Mature Height" value={wiki.basic_info?.mature_height} />
                <InfoRow label="Mature Spread" value={wiki.basic_info?.mature_spread} />
                <InfoRow label="Leaf Type" value={wiki.basic_info?.leaf_type} />
                <InfoRow label="Flowering Season" value={wiki.basic_info?.flowering_season} />
              </Section>
            </div>

            {/* Characteristics */}
            <div className="mx-4 bg-white rounded-2xl overflow-hidden border border-[#e8ede6]">
              <Section icon={Star} title="Characteristics">
                <div className="space-y-2.5">
                  <ScoreBar label="Nativity" score={wiki.characteristics?.nativity} />
                  <ScoreBar label="Flower" score={wiki.characteristics?.flower} />
                  <ScoreBar label="Fruit" score={wiki.characteristics?.fruit} />
                </div>
                {wiki.characteristics?.leaf_color && (
                  <p className="mt-3 text-xs text-[#6b8f71]">
                    <span className="font-medium text-[#1a2e1a]">Leaf color: </span>
                    {wiki.characteristics.leaf_color}
                  </p>
                )}
              </Section>
            </div>

            {/* Uses */}
            {wiki.uses && (
              <div className="mx-4 bg-white rounded-2xl overflow-hidden border border-[#e8ede6]">
                <Section icon={Shield} title="Uses & Importance">
                  {wiki.uses.ecological && (
                    <div className="mb-2">
                      <span className="text-[10px] font-bold text-[#2d6a4f] uppercase tracking-wider">Ecological</span>
                      <p className="text-xs text-[#4a6741] mt-0.5">{wiki.uses.ecological}</p>
                    </div>
                  )}
                  {wiki.uses.timber && (
                    <div className="mb-2">
                      <span className="text-[10px] font-bold text-[#2d6a4f] uppercase tracking-wider">Timber</span>
                      <p className="text-xs text-[#4a6741] mt-0.5">{wiki.uses.timber}</p>
                    </div>
                  )}
                  {wiki.uses.medicinal && (
                    <div className="mb-2">
                      <span className="text-[10px] font-bold text-[#2d6a4f] uppercase tracking-wider">Medicinal</span>
                      <p className="text-xs text-[#4a6741] mt-0.5">{wiki.uses.medicinal}</p>
                    </div>
                  )}
                  {wiki.uses.food && (
                    <div>
                      <span className="text-[10px] font-bold text-[#2d6a4f] uppercase tracking-wider">Food</span>
                      <p className="text-xs text-[#4a6741] mt-0.5">{wiki.uses.food}</p>
                    </div>
                  )}
                </Section>
              </div>
            )}

            {/* Popular Questions */}
            {wiki.popular_questions?.length > 0 && (
              <div className="mx-4 bg-white rounded-2xl overflow-hidden border border-[#e8ede6]">
                <Section icon={HelpCircle} title="Popular Questions">
                  {wiki.popular_questions.map((item, i) => (
                    <FAQItem key={i} q={item.q} a={item.a} />
                  ))}
                </Section>
              </div>
            )}

            {/* Common Problems */}
            {wiki.common_problems?.length > 0 && (
              <div className="mx-4 bg-white rounded-2xl overflow-hidden border border-[#e8ede6]">
                <Section icon={AlertTriangle} title="Common Problems">
                  {wiki.common_problems.map((p, i) => (
                    <div key={i} className="mb-3 last:mb-0">
                      <div className="flex items-center gap-2 mb-1">
                        <span className="text-xs font-semibold text-[#1a2e1a]">{p.name}</span>
                        <span className={`text-[10px] px-2 py-0.5 rounded-full font-medium ${
                          p.severity === "High"   ? "bg-red-100 text-red-700" :
                          p.severity === "Medium" ? "bg-amber-100 text-amber-700" :
                          "bg-green-100 text-green-700"
                        }`}>{p.severity}</span>
                      </div>
                      <p className="text-xs text-[#6b8f71] leading-relaxed">{p.description}</p>
                    </div>
                  ))}
                </Section>
              </div>
            )}
          </div>
        )}

        {/* ══ CARE TAB ══ */}
        {activeTab === "care" && wiki && !wikiLoading && (
          <div className="mt-4 space-y-3">

            {/* Care Profile */}
            <div className="mx-4 bg-white rounded-2xl overflow-hidden border border-[#e8ede6]">
              <Section icon={Sprout} title="Care Profile">
                {/* Difficulty */}
                <div className="mb-4 p-3 bg-[#f8faf7] rounded-xl text-center">
                  <div className="flex justify-center mb-1">
                    {[1,2,3].map(i => (
                      <div key={i} className={`w-8 h-8 rounded-full mx-0.5 flex items-center justify-center text-sm ${
                        wiki.care_profile?.difficulty === "Easy"   && i <= 1 ? "bg-[#2d6a4f] text-white" :
                        wiki.care_profile?.difficulty === "Moderate" && i <= 2 ? "bg-[#2d6a4f] text-white" :
                        wiki.care_profile?.difficulty === "Expert"  ? "bg-[#2d6a4f] text-white" :
                        "bg-[#e8ede6] text-[#6b8f71]"
                      }`}>
                        {["🌱","🌿","🌳"][i-1]}
                      </div>
                    ))}
                  </div>
                  <p className="text-sm font-bold text-[#1a2e1a]">{wiki.care_profile?.difficulty}</p>
                  <p className="text-xs text-[#6b8f71] mt-0.5">{wiki.care_profile?.difficulty_note}</p>
                </div>

                {/* Care chips */}
                <div className="grid grid-cols-2 gap-2 mb-3">
                  <CareChip icon={Droplets} label="Watering" value={wiki.care_profile?.watering} color="bg-blue-50 text-blue-700" />
                  <CareChip icon={Sun} label="Sunlight" value={wiki.care_profile?.sunlight} color="bg-amber-50 text-amber-700" />
                  <CareChip icon={Thermometer} label="Temperature" value={wiki.care_profile?.temperature} color="bg-orange-50 text-orange-700" />
                  <CareChip icon={Wind} label="Hardiness" value={wiki.care_profile?.hardiness_zones} color="bg-purple-50 text-purple-700" />
                </div>

                <InfoRow label="Soil" value={wiki.care_profile?.soil} />
                <InfoRow label="Fertilizer" value={wiki.care_profile?.fertilizer} />
              </Section>
            </div>

            {/* How-Tos */}
            {wiki.how_tos?.length > 0 && (
              <div className="mx-4 bg-white rounded-2xl overflow-hidden border border-[#e8ede6]">
                <Section icon={BookOpen} title="How-Tos">
                  {wiki.how_tos.map((ht, i) => (
                    <div key={i} className="mb-4 last:mb-0">
                      <p className="text-xs font-semibold text-[#1a2e1a] mb-2">{ht.title}</p>
                      <ol className="space-y-1.5">
                        {ht.steps.map((step, j) => (
                          <li key={j} className="flex items-start gap-2">
                            <span className="w-5 h-5 bg-[#2d6a4f] text-white text-[10px] rounded-full flex items-center justify-center flex-shrink-0 mt-0.5">{j+1}</span>
                            <p className="text-xs text-[#4a6741] leading-relaxed">{step}</p>
                          </li>
                        ))}
                      </ol>
                    </div>
                  ))}
                </Section>
              </div>
            )}

            {/* Adaptation Strategies */}
            {wiki.adaptation_strategies && (
              <div className="mx-4 bg-[#f0f7f4] rounded-2xl border border-[#c8ddd0] p-4">
                <div className="flex items-center gap-2 mb-2">
                  <Shield className="w-4 h-4 text-[#2d6a4f]" />
                  <span className="text-xs font-semibold text-[#2d6a4f] uppercase tracking-wider">Adaptation Strategies</span>
                </div>
                <p className="text-xs text-[#3d5e44] leading-relaxed">{wiki.adaptation_strategies}</p>
              </div>
            )}
          </div>
        )}

        {/* ══ INFO TAB ══ */}
        {activeTab === "info" && (
          <div className="mt-4 space-y-3">

            {/* Tree record data */}
            <div className="mx-4 bg-white rounded-2xl overflow-hidden border border-[#e8ede6]">
              <Section icon={TreePine} title="Tree Record">
                <InfoRow label="Tree ID" value={`#${tree.id}`} />
                <InfoRow label="Common Name" value={tree.common_name} />
                <InfoRow label="Scientific Name" value={tree.scientific_name} />
                <InfoRow label="Health Status" value={tree.health_status} />
                <InfoRow label="DBH" value={tree.dbh_cm ? `${tree.dbh_cm} cm` : null} />
                <InfoRow label="Height" value={tree.height_m ? `${tree.height_m} m` : null} />
                <InfoRow label="Biomass" value={tree.biomass_kg ? `${tree.biomass_kg.toFixed(2)} kg` : null} />
                <InfoRow label="Carbon Stock" value={tree.carbon_kg ? `${tree.carbon_kg.toFixed(2)} kg CO₂` : null} />
                <InfoRow label="Barangay" value={tree.barangay} />
                <InfoRow label="City" value={tree.city} />
                <InfoRow label="Province" value={tree.province} />
                <InfoRow label="Date Recorded" value={tree.date_recorded ? format(new Date(tree.date_recorded), "MMMM d, yyyy") : null} />
              </Section>
            </div>

            {/* Notes */}
            {tree.notes && (
              <div className="mx-4 bg-white rounded-2xl border border-[#e8ede6] p-4">
                <p className="text-[10px] font-bold text-[#2d6a4f] uppercase tracking-wider mb-2">Field Notes</p>
                <p className="text-xs text-[#4a6741] leading-relaxed">{tree.notes}</p>
              </div>
            )}

            {/* Health History */}
            {logs.length > 0 && (
              <div className="mx-4 bg-white rounded-2xl overflow-hidden border border-[#e8ede6]">
                <Section icon={Calendar} title="Health History">
                  {logs.map((log) => (
                    <div key={log.id} className="mb-3 last:mb-0 p-3 bg-[#f8faf7] rounded-xl">
                      <div className="flex justify-between items-center mb-1">
                        <span className="text-xs font-medium text-[#1a2e1a]">
                          {log.assessed_date ? format(new Date(log.assessed_date), "MMM d, yyyy") : ""}
                        </span>
                        <span className={`text-[10px] px-2 py-0.5 rounded-full font-semibold ${
                          log.condition === "Healthy" ? "bg-emerald-100 text-emerald-700" :
                          log.condition === "Fair"    ? "bg-amber-100 text-amber-700" :
                          "bg-red-100 text-red-700"
                        }`}>{log.condition}</span>
                      </div>
                      {log.assessed_by && <p className="text-[10px] text-[#6b8f71]">By {log.assessed_by}</p>}
                      {log.notes && <p className="text-xs text-[#4a6741] mt-1">{log.notes}</p>}
                    </div>
                  ))}
                </Section>
              </div>
            )}
          </div>
        )}

        {/* ══ HISTORY TAB ══ */}
        {activeTab === "history" && wiki && !wikiLoading && (
          <div className="mt-4 space-y-3">

            {wiki.history_and_legends && (
              <div className="mx-4 bg-white rounded-2xl overflow-hidden border border-[#e8ede6]">
                <Section icon={History} title="History & Legends" defaultOpen={true}>
                  <p className="text-xs text-[#4a6741] leading-relaxed">{wiki.history_and_legends}</p>
                </Section>
              </div>
            )}

            {wiki.name_story && (
              <div className="mx-4 bg-white rounded-2xl overflow-hidden border border-[#e8ede6]">
                <Section icon={BookOpen} title="Name Story" defaultOpen={true}>
                  <p className="text-xs text-[#4a6741] leading-relaxed">{wiki.name_story}</p>
                </Section>
              </div>
            )}

            {wiki.symbolism && (
              <div className="mx-4 bg-white rounded-2xl overflow-hidden border border-[#e8ede6]">
                <Section icon={Star} title="Symbolism" defaultOpen={true}>
                  <p className="text-xs text-[#4a6741] leading-relaxed">{wiki.symbolism}</p>
                </Section>
              </div>
            )}

            {/* Decorative quote */}
            <div className="mx-4 bg-gradient-to-br from-[#2d6a4f] to-[#52b788] rounded-2xl p-5 text-white">
              <p className="text-2xl mb-2 opacity-50">"</p>
              <p className="text-sm italic leading-relaxed opacity-90">
                Trees are poems the earth writes upon the sky.
              </p>
              <p className="text-xs opacity-60 mt-2">— Khalil Gibran</p>
            </div>
          </div>
        )}

        {/* ── Footer ── */}
        <p className="text-center text-[10px] text-[#6b8f71] mt-8 pb-4">
          TreeTrace · Panabo City Urban Forest Inventory · Tree #{tree.id}
        </p>
      </div>
    </div>
  );
}
