/*
  PUBLIC SITE CONFIGURATION
  TRAILER URL: CHANGE THIS AFTER THE YOUTUBE UPLOAD
  Paste the full YouTube watch URL into trailerUrl. Every trailer button updates from this single value.
*/
window.ACA_SITE_CONFIG = Object.freeze({
  trailerUrl: "https://youtu.be/c00JftQTui8",
  githubUrl: "https://github.com/usw344/A-Cut-Above-Lawn-Mowing-Startup-public",
  steamUrl: "https://store.steampowered.com/app/3807260/A_Cut_Above_Mow__Grow/",
  itchUrl: "https://sologamedev873.itch.io/a-cut-above-mow-and-grow"
});

const config = window.ACA_SITE_CONFIG;
const linkMap = {
  github: config.githubUrl,
  steam: config.steamUrl,
  itch: config.itchUrl
};

Object.entries(linkMap).forEach(([name, url]) => {
  document.querySelectorAll(`[data-link="${name}"]`).forEach((link) => {
    if (url) {
      link.href = url;
      link.removeAttribute("aria-disabled");
    } else {
      link.removeAttribute("href");
      link.setAttribute("aria-disabled", "true");
      link.addEventListener("click", (event) => event.preventDefault());
    }
  });
});

const getYouTubeVideoId = (value) => {
  if (!value) return null;

  try {
    const url = new URL(value);
    const host = url.hostname.replace(/^www\./, "");
    let videoId = null;

    if (host === "youtu.be") {
      videoId = url.pathname.split("/").filter(Boolean)[0];
    } else if (host === "youtube.com" || host === "m.youtube.com") {
      if (url.pathname === "/watch") videoId = url.searchParams.get("v");
      if (url.pathname.startsWith("/embed/")) videoId = url.pathname.split("/")[2];
      if (url.pathname.startsWith("/shorts/")) videoId = url.pathname.split("/")[2];
    }

    return /^[A-Za-z0-9_-]{11}$/.test(videoId || "") ? videoId : null;
  } catch {
    return null;
  }
};

const trailerSection = document.querySelector("[data-trailer-section]");
const trailerEmbed = document.querySelector("[data-trailer-embed]");
const trailerExternal = document.querySelector("[data-trailer-external]");
const trailerLinks = document.querySelectorAll('[data-link="trailer"]');
const trailerVideoId = getYouTubeVideoId(config.trailerUrl);

if (trailerVideoId && trailerSection && trailerEmbed) {
  const iframe = document.createElement("iframe");
  iframe.src = `https://www.youtube-nocookie.com/embed/${trailerVideoId}?rel=0`;
  iframe.title = "A Cut Above: Mow & Grow v0.3 gameplay showcase";
  iframe.loading = "lazy";
  iframe.referrerPolicy = "strict-origin-when-cross-origin";
  iframe.allow = "accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share";
  iframe.allowFullscreen = true;
  trailerEmbed.appendChild(iframe);
  trailerSection.hidden = false;

  trailerLinks.forEach((link) => {
    link.href = "#trailer";
    link.removeAttribute("aria-disabled");
    link.textContent = "Watch the showcase";
  });

  if (trailerExternal) trailerExternal.href = config.trailerUrl;
} else {
  trailerLinks.forEach((link) => {
    link.removeAttribute("href");
    link.setAttribute("aria-disabled", "true");
    link.addEventListener("click", (event) => event.preventDefault());
  });
}

document.querySelectorAll("[data-year]").forEach((item) => {
  item.textContent = new Date().getFullYear();
});

const header = document.querySelector("[data-header]");
const updateHeader = () => header?.classList.toggle("is-scrolled", window.scrollY > 24);
updateHeader();
window.addEventListener("scroll", updateHeader, { passive: true });

const dialog = document.querySelector("[data-lightbox-dialog]");
const dialogImage = dialog?.querySelector("img");
const dialogCaption = dialog?.querySelector("p");

document.querySelectorAll("[data-lightbox]").forEach((shot) => {
  shot.addEventListener("click", () => {
    if (!dialog || !dialogImage || !dialogCaption) return;
    dialogImage.src = shot.dataset.lightbox;
    dialogImage.alt = shot.querySelector("img")?.alt || "Gameplay screenshot";
    dialogCaption.textContent = shot.dataset.caption || "";
    dialog.showModal();
  });
});

dialog?.querySelector("[data-lightbox-close]")?.addEventListener("click", () => dialog.close());
dialog?.addEventListener("click", (event) => {
  if (event.target === dialog) dialog.close();
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && dialog?.open) dialog.close();
});
