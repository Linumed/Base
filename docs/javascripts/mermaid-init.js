// Renders diagrams marked class="mermaid-diagram" using the self-hosted mermaid.min.js
// loaded just before this file (see mkdocs.yml extra_javascript).
//
// Deliberately not using Material for MkDocs's own built-in Mermaid integration
// (markdown_extensions -> pymdownx.superfences custom_fences with class: mermaid).
// Material's bundled JS watches for exactly that class name and, when found, always
// dynamically imports its renderer from unpkg.com at runtime - a real external CDN
// dependency invisible to a static asset scan, confirmed by grepping Material's own
// bundle.*.min.js for "unpkg.com/mermaid" (found while building this, 2026-08-19).
// That breaks this project's own "no external resources from foreign servers, no
// phone-home" rule (CONVENTIONS.md) exactly like the Google Fonts CDN load fixed in #55 -
// only less visible, since it is a JS-triggered network request, not a static
// <link>/<script> tag. Using a different class name here ("mermaid-diagram" instead of
// "mermaid") keeps Material's own detection from ever firing.
document.addEventListener("DOMContentLoaded", function () {
  if (!window.mermaid) {
    return;
  }
  // pymdownx.superfences wraps fence content as <pre class="mermaid-diagram"><code>...
  // </code></pre>. mermaid.run() reads the target element's innerHTML as the diagram
  // source, so without this it gets the literal string "<code>graph TB...</code>" and
  // fails with "No diagram type detected" (found 2026-08-19, live site showed the error
  // bomb on both diagrams in ARCHITECTURE.md). Unwrap the <code> child first so mermaid
  // sees plain diagram text, matching the bare `<pre class="mermaid">source</pre>` shape
  // its own docs assume.
  document.querySelectorAll(".mermaid-diagram").forEach(function (el) {
    var code = el.querySelector("code");
    if (code) {
      el.textContent = code.textContent;
    }
  });
  mermaid.initialize({ startOnLoad: false, theme: "default" });
  mermaid.run({ querySelector: ".mermaid-diagram" });
});
