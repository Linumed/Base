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
(function () {
  // Teal to match the site's own primary color (mkdocs.yml theme.palette primary: teal),
  // so the diagrams look like part of this site instead of mermaid's stock purple/grey.
  var themeVariablesLight = {
    primaryColor: "#e0f2f1",
    primaryTextColor: "#0f2b2a",
    primaryBorderColor: "#00897b",
    lineColor: "#4d7a75",
    secondaryColor: "#b2dfdb",
    tertiaryColor: "#ffffff",
    clusterBkg: "#f3fbfa",
    clusterBorder: "#4d7a75",
    fontFamily:
      "-apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Helvetica, Arial, sans-serif",
  };
  var themeVariablesDark = {
    primaryColor: "#0f3a37",
    primaryTextColor: "#e8f5f3",
    primaryBorderColor: "#4db6ac",
    lineColor: "#7fcac3",
    secondaryColor: "#123a38",
    tertiaryColor: "#1b1b1b",
    clusterBkg: "#132524",
    clusterBorder: "#4db6ac",
    fontFamily:
      "-apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Helvetica, Arial, sans-serif",
  };

  // Material for MkDocs stores the active palette as data-md-color-scheme on <body>
  // ("default" = light, "slate" = dark) and updates it live when the reader clicks the
  // light/dark toggle - see mkdocs.yml theme.palette. Diagrams re-render on that change
  // too, not just on page load, so switching the toggle doesn't leave them stuck in the
  // wrong palette.
  function isDark() {
    return document.body.getAttribute("data-md-color-scheme") === "slate";
  }

  function renderAll() {
    if (!window.mermaid) {
      return;
    }
    mermaid.initialize({
      startOnLoad: false,
      theme: "base",
      themeVariables: isDark() ? themeVariablesDark : themeVariablesLight,
      flowchart: { curve: "basis" },
    });
    document.querySelectorAll(".mermaid-diagram").forEach(function (el) {
      // First run: unwrap pymdownx.superfences' <pre class="mermaid-diagram"><code>...
      // </code></pre>. mermaid.run() reads the target element's innerHTML as the diagram
      // source, so without this it gets the literal string "<code>graph TB...</code>" and
      // fails with "No diagram type detected" (found 2026-08-19, Base#59). Cache the real
      // source in a data attribute so a later theme-change re-render has plain text to
      // start from again, not the previous run's rendered SVG.
      if (!el.dataset.mermaidSrc) {
        var code = el.querySelector("code");
        el.dataset.mermaidSrc = code ? code.textContent : el.textContent;
      }
      el.removeAttribute("data-processed");
      el.textContent = el.dataset.mermaidSrc;
    });
    mermaid.run({ querySelector: ".mermaid-diagram" });
  }

  document.addEventListener("DOMContentLoaded", renderAll);
  new MutationObserver(renderAll).observe(document.body, {
    attributes: true,
    attributeFilter: ["data-md-color-scheme"],
  });
})();
