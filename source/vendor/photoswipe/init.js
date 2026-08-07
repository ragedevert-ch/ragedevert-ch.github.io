import PhotoSwipeLightbox from "./photoswipe-lightbox.esm.js";

const lightbox = new PhotoSwipeLightbox({
  gallery: "#photo-gallery",
  children: "a",
  arrowPrevTitle: "Précédent",
  arrowNextTitle: "Suivant",
  closeTitle: "Fermer",
  zoomTitle: "Zoom",
  pswpModule: () => import("./photoswipe.esm.js"),
});

// Empty thumb alts avoid double announcement with the link aria-label.
// PhotoSwipe copies img alt into the lightbox slide, so fill it from the link label.
lightbox.addFilter("domItemData", (itemData, _element, linkEl) => {
  if (itemData.alt) return itemData;
  if (!linkEl) return itemData;

  const label = linkEl.getAttribute("aria-label") || "";
  if (!label) return itemData;

  itemData.alt = label.replace(/^Voir la photo:\s*/i, "").replace(/^Voir la photo\s+/i, "Photo ");

  return itemData;
});

lightbox.init();
