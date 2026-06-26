# AGENTS.md

Project-specific guidance for the Rage de Vert static site.

## Project

- Static site for Rage de Vert built with Middleman.
- Current GitHub Pages review host: `http://new.ragedevert.ch`.
- Final production canonical host: `https://www.ragedevert.ch`; `https://new.ragedevert.ch` is only a temporary review host. Keep `config.rb`, `source/robots.txt`, and `source/CNAME` aligned with the canonical host.
- Source lives in `source/`; generated output goes to `build/`.
- Do not commit, push, or create branches unless explicitly asked.

## Commands

- Build: `bundle exec middleman build`
- Local server: `bundle exec middleman server --port 4567`
- Link check after build: `ruby scripts/check_static_links.rb build`
- Prepare gallery photos after adding originals: `ruby scripts/prepare_gallery_images.rb`
- Prepare logo and favicon images from the source logo: `ruby scripts/prepare_logo_images.rb`
- Prepare decorative vegetable images: `ruby scripts/prepare_vegetable_images.rb [source_directory]`
- Curate homepage gallery picks by listing committed `galerie-*.jpg` filenames in `data/home_gallery.yml`.

## Prerequisites

- Ruby version is pinned in `.ruby-version`.
- Install dependencies with `bundle install`.
- ImageMagick is required for gallery, logo, and vegetable image preparation scripts (`brew install imagemagick` on macOS).

## Review checklist

- Source/content change: run `bundle exec middleman build` and `ruby scripts/check_static_links.rb build`.
- Visual/layout change: inspect desktop and mobile views in a browser, including the mobile menu and prominent headings.
- Gallery change: run `ruby scripts/prepare_gallery_images.rb`, verify `data/gallery.yml`, then curate `data/home_gallery.yml` if homepage picks should change.
- Logo/icon change: update `source/assets/images/logo-source.png`, run `ruby scripts/prepare_logo_images.rb`, then build and check links.
- Link/document change: keep `/s/` document filenames stable and clean, update all references together, and run the link checker after build.
- SEO/domain change: confirm the canonical host first, then update `config.rb`, `source/robots.txt`, and `source/CNAME` together.

## Design direction

The visual language should feel organic, direct, and local: vegetables, soil, simple association life. Prefer quiet polish over startup-slick effects.

### Palette

Use the CSS variables in `source/assets/css/style.css` as the source of truth:

- `--color-green-dark: #1f5f38` — primary vegetable green; use for main headings and brand text.
- `--color-green: #287044` — interaction/secondary green, deep enough for small links on cream/sand.
- `--color-leaf: #b7d45d`, `--color-leaf-soft: #dfeaa9`, and `--color-leaf-hover: #c6df72` — leaf accents for active states, primary buttons, and small highlights; keep dark ink text on top.
- `--color-soil: #875a35` — warm soil brown for eyebrow/meta text.
- `--color-soil-dark: #443021` — readable body/supporting text on white areas.
- `--color-ink: #10281a` — dark forest green used for footer/background blocks and high-contrast text.
- `--color-cream: #fcf7ea` and `--color-sand: #f0e4cc` — warm off-white section backgrounds.
- `--color-white: #ffffff` — true white, especially where transparent black line art/logos need a clean backdrop.

### Typography

- Use the self-hosted open-source web fonts in `source/assets/fonts/`: `Source Serif 4` for title/display text and `IBM Plex Mono` for compact accent text such as nav, labels, buttons, and footer headings.
- Keep paragraphs/body copy on the sans/system stack for readability.
- Do not use the bundled branding OTF files (`Minion Pro`, `PP Fraktion Mono`) unless a web-embedding license is confirmed.

### French copy style

- Write in clear, natural French with an épicène/égalitaire style inspired by the Canton of Neuchâtel guidance:
  - https://www.ne.ch/themes/vie-quotidienne-et-famille/egalite/egalite-dans-le-langage
  - https://www.ne.ch/sites/default/files/2025-11/2022_OPFE_Guide%20d'écriture%20inclusive_0.pdf
- Prefer neutral or collective wording (`membres`, `personnes`, `équipe`, `association`, `abonnements`) and simple reformulations over heavy marks.
- Use doublets when they read naturally (`jardinières et jardiniers`, `abonné·es`) but avoid overloading short marketing copy.
- Avoid neo-pronouns such as `iel`/`iels` in public site copy; rewrite the sentence instead.
- Swiss-French punctuation does not require extra spacing before `!`, `?`, or `:`; do not add those spaces just for typographic French conventions.
- For testimonials, keep the author’s meaning and voice, but excerpts may be lightly edited for length, clarity, typography, and site-wide language style.

### Layout/style notes

- Keep the sticky site header text-only and compact, on a warm cream background. The detailed logo belongs large in the homepage hero.
- Homepage hero and page headers use white backgrounds so content starts cleanly under the cream header. The hero logo sits directly on white, with the hero title in dark ink to echo the black line-art logo and supporting text in soil brown.
- Footer banner uses `banner.webp` uncropped, inset with white breathing room, directly above the dark green footer body.
- Prefer flat structure over nested card stacks: soft borders, warm backgrounds, clear dividers/spacing, and little or no shadow. Use shadows only when they already serve a clear media/gallery affordance.
- Keep grids calm and intentional. Similar items should have equal-width/equal-height cards where practical; avoid layouts where labels or long values create awkward ragged columns.
- On mobile, stack content early and preserve comfortable tap targets. Check narrow screens for unwanted word or hyphen breaks in prominent copy.
- Avoid native CSS functions such as `min()` in authored CSS because SassC can misparse them during Middleman builds. `clamp()` is already used in the stylesheet; continue avoiding `min()` specifically and use `width` + `max-width` fallbacks when needed.
- Keep `/s/` document URLs stable once published, using clean `ragdevert-*` filenames for maintained documents.
- Keep `/vendor/photoswipe/` ES modules unminified in build config.

### Established page patterns

- New or reworked pages should follow the established rhythm from `/`, `/galerie/`, and `/contact/`: white page header, warm cream/sand content sections, large serif headings, compact mono eyebrows, and flat bordered panels for practical information.
- Homepage patterns:
  - Keep the hero direct and association-focused; avoid extra marketing layers.
  - Keep the subscription/facts areas flat and scannable, with simple rows or panels rather than nested mini-cards.
  - Curate the homepage gallery through `data/home_gallery.yml` using committed `galerie-*.jpg` filenames.
- Paniers patterns:
  - Treat `/paniers/` as the main offer page: make the subscription basics, sizes/prices, distribution choices, and trial period visible before secondary practical details.
  - Do not place the flyer as a primary hero CTA; keep the main CTA focused on inscription and tariffs, then group the flyer with other useful documents.
  - Keep distribution practical and maintainable: flat choice cards plus a depot list with exact address links and supplements. Do not embed a multi-marker map or bike-delivery zone unless the association provides a maintained source of truth.
  - Keep the “valeur des paniers” table as a linked supporting document rather than a large inline image.
- Gallery patterns:
  - Use optimized local images from `source/assets/images/galerie/` and thumbnails from `thumbs/`.
  - Keep PhotoSwipe for gallery browsing; do not reintroduce remote Squarespace images.
  - Keep videos as quiet links unless there is a clear reason to embed them.
- Culture patterns:
  - Keep the page chronological and place-based: Jardin de la Main, Pierre-à-Bot, Serrières, then Thielle-Wavre.
  - Present Thielle-Wavre as the current production/culture site and the Jardin de la Main as the historical city anchor and distribution place.
  - Preserve the 2015 context from the source page: Martin Ott, le domaine du Grand Montmirail, la communauté Don Camillo, et Perspective Plus.
  - Keep the Agridea/FiBL 2020 portrait link to `/s/ragdevert-portrait-agridea-fibl.pdf`.
  - Use the local `source/assets/images/culture/champs-rage-de-vert.webp` image unless a better local culture image is intentionally added.
- Contact patterns:
  - Keep contact methods as flat tiles, with the email primary and centered on desktop.
  - Keep the official postal address next to the bank details in the administrative area, not inside the practical access/map section.
  - Access maps should show practical visitor destinations using the maintained depot map embed from `membres.ragedevert.ch`/admin data. Do not replace these with Google Maps iframe embeds; regular Google Maps links may remain when useful.
  - Current GPS points for fallback links: Les champs `47.02047534040518, 7.029074674516895`; Le Jardin de la Main `46.98899814230239, 6.9197201203696705`.
  - Keep the Thielle access PDF (`/s/ragdevert-plan-acces-thielle.pdf`) on the fields card. Do not reintroduce the old Jardin plan image unless explicitly requested.
- Budget patterns:
  - Keep money/salary content transparent but scannable: start with a short explanation, then use flat figure panels for budget totals and major expense categories.
  - Use rounded figures from the source page unless refreshed by the association: annual budget `220’000 CHF`, personnel `150’000 CHF`, cultures `25’000 CHF`, loyers `12’000 CHF`, matériel `11’000 CHF`, frais divers `18’000 CHF`.
  - Keep salary wording respectful and centered on the work of the `équipe maraîchère`; avoid turning salary transparency into either guilt or marketing hype.
  - Include the subscription CTA that explains voluntary basket-price supplements: base price, `+ 1.–`, `+ 2.–`, `+ 4.–`, and `+ 8.–` per basket, shown as yearly effects over 42 baskets.
  - Use the current Neuchâtel contract-type PDF link: `https://rsn.ne.ch/DATA/program/books/rsne/pdf/225.43.pdf`.
- Équipe patterns:
  - Keep the page concise and human-scaled: introduce the current `équipe maraîchère`, then separate practical bénévolat/stage information from the committee section.
  - Use neutral wording such as `équipe maraîchère`, `personnes motivées`, `bénévolat`, and `stages`; avoid masculine-default phrases such as `homme à tout faire` in public copy.
  - Keep field/stage contact directed to `jardin@ragedevert.ch` unless the association changes the operational address.
  - Keep team photos flat and lightly framed, without heavy card shadows.

### Implementation best practices

- Do not edit `build/` directly; it is generated by Middleman.
- Keep content and assets local unless an external service is intentional (for example `membres.ragedevert.ch`, maintained depot map embeds, social links, Google Maps links, Vimeo links).
- Use semantic HTML: one clear `h1` per page, ordered headings, real lists for lists, `address` for addresses, descriptive link text, useful `alt` text, `aria-current` for the active navigation link, and `title` attributes on iframes.
- Keep gallery links distinguishable for assistive technologies. Curated descriptive alt text is best; when unavailable, use distinct fallback labels rather than repeated generic labels.
- Respect reduced-motion preferences and keep visible `:focus-visible` states on custom controls.
- Localize third-party UI labels when they are exposed to users or assistive technologies.
- Prefer existing helpers and data files over duplicating markup. Add new data files only when they reduce repeated page code.
- Generated data boundaries: `data/gallery.yml` comes from `scripts/prepare_gallery_images.rb`, `data/vegetables.yml` comes from `scripts/prepare_vegetable_images.rb`, and `data/home_gallery.yml` is manually curated.
- Generated logo boundaries: `source/assets/images/logo-source.png` is the high-resolution source and is ignored from the generated site; `logo.webp`, favicons, Apple touch icon, and `favicon.ico` come from `scripts/prepare_logo_images.rb`.
- Asset boundaries: optimized gallery files and WebP thumbnails are committed. Keep large originals outside the repository; unused files under `source/assets/images/` are still copied into `build/` unless moved or ignored.
- Keep `/vendor/photoswipe/` ES modules unminified in build config.
- For prominent French compounds that should not split awkwardly, use a non-breaking hyphen (`‑`) selectively, for example `Écrivez‑nous` and `appelez‑nous`.
- After meaningful source changes, run `bundle exec middleman build` and `ruby scripts/check_static_links.rb build`. For visual/layout changes, also inspect desktop and mobile views in a browser.
