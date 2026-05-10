import landingHtmlRaw from "@/landing/index.html?raw";

const landingHtml = landingHtmlRaw
  .replace("<head>", '<head><base href="/landing/">')
  .replace("window.location.href = path;", "window.top.location.href = path;")
  .replace('href="/public" class="btn-primary"', 'href="/public" target="_top" class="btn-primary"');

export default function SystemHome() {
  return (
    <iframe
      title="TreeTrace website"
      srcDoc={landingHtml}
      className="h-screen w-full border-0"
    />
  );
}
