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

lightbox.init();
