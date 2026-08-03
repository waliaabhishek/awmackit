const target = new URLSearchParams(location.search).get("target");
if (target?.startsWith("powertools-link://")) {
  location.replace(target);
  setTimeout(() => window.close(), 1200);
}
