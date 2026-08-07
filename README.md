# Rage de Vert

Static Middleman site for Rage de Vert, intended for GitHub Pages.

The current review host is `http://new.ragedevert.ch`. The final production canonical host is `https://www.ragedevert.ch`; `https://new.ragedevert.ch` is only a temporary review host.

## Prerequisites

- Ruby version from `.ruby-version`
- Bundler
- ImageMagick for image preparation scripts (`brew install imagemagick` on macOS)

## Setup

```sh
bundle install
```

## Development

```sh
bundle exec middleman server --port 4567
```

The local site runs at `http://localhost:4567`.

## Gallery photos

After adding high-resolution photos to `source/assets/images/galerie/`, prepare them for the site:

```sh
ruby scripts/prepare_gallery_images.rb
```

The script:

1. reads source images from `source/assets/images/galerie/`;
2. generates optimized full-size images in `source/assets/images/galerie/`;
3. generates smaller WebP thumbnails in `source/assets/images/galerie/thumbs/`;
4. orders new images newest first;
5. updates `data/gallery.yml`.

Commit the optimized gallery images, WebP thumbnails, and `data/gallery.yml`. Keep large originals outside the repository after preparation.

The homepage preview is curated separately in `data/home_gallery.yml`; list committed `galerie-*.jpg` filenames there to pick a varied set of fields, vegetables, and people at work.

## Logo and icons

The high-resolution logo source is kept in `source/assets/images/logo-source.png` and ignored from the generated site. Regenerate the web logo, favicons, and Apple touch icon with:

```sh
ruby scripts/prepare_logo_images.rb
```

## Gribouille newsletters

Public weekly Gribouilles are pulled from the CSA Admin Atom feed and materialised into the repo:

```sh
ruby scripts/sync_gribouilles.rb
```

Local CSA Admin preview:

```sh
GRIBOUILLE_FEED_URL='https://membres.ragedevert.test/newsletters.atom?template_id=9' \
  ruby scripts/sync_gribouilles.rb
```

The script downloads entry HTML images and PDF attachments immediately, rewrites image paths to local assets, and updates:

- `data/gribouilles.yml`
- `data/gribouille_entries/<id>.yml`
- `source/assets/images/gribouille/<id>/`
- `source/s/gribouille/<id>/`

The archive page is `/gribouille/`. A daily GitHub Action (`.github/workflows/sync-gribouilles.yml`) runs the same sync against production and commits when content changes; the existing Pages deploy workflow then rebuilds the site.

## Build and validation

```sh
bundle exec middleman build
ruby scripts/check_static_links.rb build
```

The generated site is written to `build/` and deployed by GitHub Actions.
