import { useEffect } from "react";
import landingHtmlRaw from "@/landing/index.html?raw";

const landingHtml = landingHtmlRaw
  .replace("<head>", '<head><base href="/landing/">')
  .replace("window.location.href = path;", "window.top.location.href = path;")
  .replace('href="/public" class="btn-primary"', 'href="/public" target="_top" class="btn-primary"');

export default function SystemHome() {
  useEffect(() => {
    // Hide parent scrollbar to avoid double scrollbar issues
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = "";
    };
  }, []);

  return (
    <iframe
      title="TreeTrace website"
      srcDoc={landingHtml}
      className="h-screen w-screen block border-0 m-0 p-0 overflow-hidden"
    />
  );
}
