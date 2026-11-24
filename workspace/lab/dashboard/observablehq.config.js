// Observable Framework settings for the lab dashboard.
// The structure follows echis-dashboards. Only what the lab needs is kept.
export default {
  root: "src",
  output: "dist",
  title: "FHIR analytics codelab",
  pages: [
    {name: "Overview", path: "/index"},
    {name: "Immunization", path: "/immunization"}
  ],
  style: "style.css",
  footer: "Open Health Stack Software Foundation. Built from the analytics database that FHIR Data Pipes fills.",
  // The built site is served as plain files, so a page is /immunization.html.
  cleanUrls: false,
  sidebar: false,
  toc: false,
  pager: false,
  search: false
};
