export default function EndangeredBadge({ status, statusCode, small = false }) {
  if (!status || status === "Not Listed") return null;

  const colors = {
    CR: "bg-red-100 text-red-800 border-red-300",
    EN: "bg-orange-100 text-orange-800 border-orange-300",
    VU: "bg-yellow-100 text-yellow-800 border-yellow-300",
    LC: "bg-green-100 text-green-800 border-green-300",
  };

  const labels = {
    CR: "Critically Endangered",
    EN: "Endangered",
    VU: "Vulnerable",
    LC: "Least Concern",
  };

  const color = colors[statusCode] || "bg-gray-100 text-gray-800 border-gray-300";
  const label = small ? statusCode : (labels[statusCode] || status);

  return (
    <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full border text-xs font-semibold ${color}`}>
      {(statusCode === "CR" || statusCode === "EN") && "⚠️ "}
      {label}
    </span>
  );
}
