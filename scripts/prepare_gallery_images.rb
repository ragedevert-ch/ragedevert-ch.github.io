#!/usr/bin/env ruby
# frozen_string_literal: true

# Prepare gallery photos for the static site:
# - reads source images from source/assets/images/galerie/;
# - preserves existing generated JPEGs as source/assets/images/galerie/galerie-01.jpg, ...;
# - optimizes newly added source photos into generated JPEGs;
# - writes smaller WebP thumbnails under source/assets/images/galerie/thumbs/;
# - preserves existing data/gallery.yml order for committed gallery images;
# - sorts newly added sources newest first using EXIF, filename dates, then mtime;
# - regenerates data/gallery.yml for Middleman.

require "date"
require "fileutils"
require "open3"
require "set"
require "tmpdir"
require "yaml"

ROOT = File.expand_path("..", __dir__)
GALLERY_DIR = File.join(ROOT, "source/assets/images/galerie")
THUMB_DIR = File.join(GALLERY_DIR, "thumbs")
DATA_PATH = File.join(ROOT, "data/gallery.yml")
MAX_DIMENSION = 2_000
QUALITY = 82
THUMB_MAX_DIMENSION = 720
THUMB_QUALITY = 72
THUMB_EXTENSION = ".webp"
IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .webp].freeze
GENERATED_BASENAME = /\Agalerie-\d{2,}\.jpg\z/
LEGACY_BASENAME = /\Agalerie-\d{2,}\.(?:jpe?g|png)\z/i
GENERIC_ALT = "Image de la galerie Rage de Vert"

Candidate = Struct.new(:path, :source, :saved_entry, :saved_index, :preserve_full_size, keyword_init: true)
Entry = Struct.new(:path, :source, :date_time, :sort_date_time, :date_source, :alt, :saved_index, :preserve_full_size, keyword_init: true)

class GalleryPreparationError < StandardError; end

def image_file?(path)
  File.file?(path) && IMAGE_EXTENSIONS.include?(File.extname(path).downcase)
end

def generated_data?
  return false unless File.exist?(DATA_PATH)

  File.readlines(DATA_PATH, chomp: true).first.to_s.include?("prepare_gallery_images.rb")
end

def existing_entries
  return [] unless File.exist?(DATA_PATH)

  YAML.load_file(DATA_PATH).to_a
rescue Psych::SyntaxError
  []
end

def existing_generated_basenames
  existing_entries.filter_map do |entry|
    image = entry["image"] || entry[:image]
    File.basename(image.to_s) if image
  end.to_set
end

def sort_date_time(_source, date_time)
  date_time
end

def existing_entry_by_source
  existing_entries.each_with_object({}) do |entry, entries|
    source = existing_entry_source(entry)
    entries[source] = entry if source
  end
end

def existing_entry_indexes_by_source
  existing_entries.each_with_index.each_with_object({}) do |(entry, index), entries|
    source = existing_entry_source(entry)
    entries[source] = index if source
  end
end

def existing_entry_source(entry)
  entry["source"] || entry[:source] || existing_entry_image_basename(entry)
end

def existing_entry_image_basename(entry)
  image = entry["image"] || entry[:image]
  File.basename(image.to_s) if image
end

def require_magick!
  return if system("magick", "-version", out: File::NULL, err: File::NULL)

  raise GalleryPreparationError, "ImageMagick is required. Install it with `brew install imagemagick` on macOS."
end

def root_image_paths
  Dir.children(GALLERY_DIR).filter_map do |name|
    path = File.join(GALLERY_DIR, name)
    path if image_file?(path)
  end
end

def incoming_image_paths
  keep_generated = generated_data? ? existing_generated_basenames : Set.new

  root_image_paths.reject do |path|
    basename = File.basename(path)
    keep_generated.include?(basename) && basename.match?(GENERATED_BASENAME)
  end
end

def exif_date_time(path)
  stdout, _stderr, status = Open3.capture3("magick", "identify", "-quiet", "-format", "%[EXIF:DateTimeOriginal]", path)
  return unless status.success?

  parse_exif_date_time(stdout.strip)
end

def parse_exif_date_time(value)
  return if value.empty? || value.include?("unknown image property")

  DateTime.strptime(value, "%Y:%m:%d %H:%M:%S")
rescue Date::Error
  nil
end

def filename_date_time(path)
  basename = File.basename(path)

  if (match = basename.match(/(20\d{2})[-_ ]?(\d{2})[-_ ]?(\d{2})/))
    return DateTime.new(match[1].to_i, match[2].to_i, match[3].to_i)
  end

  nil
rescue Date::Error
  nil
end

def legacy_date_time(path)
  basename = File.basename(path)
  return unless basename.match?(LEGACY_BASENAME)

  index = basename[/\d{2,}/].to_i
  DateTime.new(2010, 1, 1) - Rational(index, 86_400)
end

def mtime_date_time(path)
  File.mtime(path).to_datetime
end

def capture_date_time(path, saved_entry)
  if saved_entry && (saved_date = saved_entry["date"] || saved_entry[:date])
    return [DateTime.parse(saved_date.to_s), "data"]
  end

  if (date_time = exif_date_time(path))
    return [date_time, "exif"]
  end

  if (date_time = filename_date_time(path))
    return [date_time, "filename"]
  end

  if (date_time = legacy_date_time(path))
    return [date_time, "legacy"]
  end

  [mtime_date_time(path), "mtime"]
end

def alt_text(source, saved_entry)
  saved_alt = saved_entry && (saved_entry["alt"] || saved_entry[:alt])
  return saved_alt if saved_alt && !saved_alt.empty?

  GENERIC_ALT
end

def source_candidates
  saved_entries = existing_entry_by_source
  saved_indexes = existing_entry_indexes_by_source
  candidates = {}

  if generated_data?
    existing_entries.each_with_index do |entry, index|
      image = entry["image"] || entry[:image]
      source = existing_entry_source(entry)
      next unless image && source

      path = File.join(GALLERY_DIR, File.basename(image.to_s))
      next unless image_file?(path)

      candidates[source] = Candidate.new(path: path, source: source, saved_entry: entry, saved_index: index, preserve_full_size: true)
    end
  end

  incoming_image_paths.each do |path|
    source = File.basename(path)
    candidates[source] = Candidate.new(
      path: path,
      source: source,
      saved_entry: saved_entries[source],
      saved_index: saved_indexes[source],
      preserve_full_size: false
    )
  end

  candidates.values
end

def entries_for_candidates(candidates)
  candidates.map do |candidate|
    date_time, date_source = capture_date_time(candidate.path, candidate.saved_entry)

    Entry.new(
      path: candidate.path,
      source: candidate.source,
      date_time: date_time,
      sort_date_time: sort_date_time(candidate.source, date_time),
      date_source: date_source,
      alt: alt_text(candidate.source, candidate.saved_entry),
      saved_index: candidate.saved_index,
      preserve_full_size: candidate.preserve_full_size
    )
  end.sort_by { |entry| entry_sort_key(entry) }
end

def entry_sort_key(entry)
  return [0, entry.saved_index] if entry.saved_index

  [1, -entry.sort_date_time.to_time.to_i, entry.source.downcase]
end

def optimize_jpeg(source, destination, max_dimension:, quality:)
  run_magick!(
    source,
    "-auto-orient",
    "-resize", "#{max_dimension}x#{max_dimension}>",
    "-background", "white",
    "-alpha", "remove",
    "-alpha", "off",
    "-strip",
    "-sampling-factor", "4:2:0",
    "-interlace", "JPEG",
    "-colorspace", "sRGB",
    "-quality", quality.to_s,
    destination
  )
end

def optimize_webp(source, destination, max_dimension:, quality:)
  run_magick!(
    source,
    "-auto-orient",
    "-resize", "#{max_dimension}x#{max_dimension}>",
    "-background", "white",
    "-alpha", "remove",
    "-alpha", "off",
    "-strip",
    "-colorspace", "sRGB",
    "-quality", quality.to_s,
    "-define", "webp:method=6",
    destination
  )
end

def run_magick!(*arguments)
  stdout, stderr, status = Open3.capture3("magick", *arguments)
  return if status.success?

  raise GalleryPreparationError, "Could not optimize #{arguments.first}: #{stdout}#{stderr}"
end

def remove_generated_images!
  root_image_paths.each { |path| FileUtils.rm_f(path) }
  FileUtils.rm_rf(THUMB_DIR)
end

def write_gallery_data(entries)
  payload = entries.each_with_index.map do |entry, index|
    filename = format("galerie-%02d.jpg", index + 1)
    thumbnail = format("galerie-%02d%s", index + 1, THUMB_EXTENSION)

    {
      "image" => "galerie/#{filename}",
      "thumbnail" => "galerie/thumbs/#{thumbnail}",
      "alt" => entry.alt,
      "date" => entry.date_time.strftime("%Y-%m-%d"),
      "source" => entry.source
    }
  end

  yaml = payload.to_yaml.sub(/\A---\n/, "")
  File.write(
    DATA_PATH,
    "# Generated by scripts/prepare_gallery_images.rb\n" \
    "# Add source photos to source/assets/images/galerie/ and run: ruby scripts/prepare_gallery_images.rb\n" \
    "#{yaml}"
  )
end

def total_size(paths)
  paths.sum { |path| File.size(path) }
end

def human_size(bytes)
  units = %w[B KB MB GB]
  size = bytes.to_f
  unit = units.shift

  while size >= 1024 && units.any?
    size /= 1024
    unit = units.shift
  end

  format("%.1f %s", size, unit)
end

begin
  require_magick!
  FileUtils.mkdir_p(GALLERY_DIR)

  candidates = source_candidates
  raise GalleryPreparationError, "No gallery sources found. Add photos to #{GALLERY_DIR} and rerun the script." if candidates.empty?

  entries = entries_for_candidates(candidates)
  source_size = total_size(candidates.map(&:path).uniq)
  optimized_paths = []
  thumbnail_paths = []

  Dir.mktmpdir("gallery-optimized") do |temp_dir|
    full_dir = File.join(temp_dir, "full")
    thumb_dir = File.join(temp_dir, "thumbs")
    FileUtils.mkdir_p(full_dir)
    FileUtils.mkdir_p(thumb_dir)

    entries.each_with_index do |entry, index|
      filename = format("galerie-%02d.jpg", index + 1)
      thumbnail = format("galerie-%02d%s", index + 1, THUMB_EXTENSION)
      output = File.join(full_dir, filename)
      thumb = File.join(thumb_dir, thumbnail)
      if entry.preserve_full_size
        FileUtils.cp(entry.path, output)
      else
        optimize_jpeg(entry.path, output, max_dimension: MAX_DIMENSION, quality: QUALITY)
      end

      optimize_webp(entry.path, thumb, max_dimension: THUMB_MAX_DIMENSION, quality: THUMB_QUALITY)
      optimized_paths << output
      thumbnail_paths << thumb
    end

    optimized_size = total_size(optimized_paths)
    thumbnail_size = total_size(thumbnail_paths)
    remove_generated_images!
    FileUtils.mkdir_p(THUMB_DIR)

    optimized_paths.each do |path|
      FileUtils.cp(path, File.join(GALLERY_DIR, File.basename(path)))
    end

    thumbnail_paths.each do |path|
      FileUtils.cp(path, File.join(THUMB_DIR, File.basename(path)))
    end

    write_gallery_data(entries)

    puts "Prepared #{entries.size} gallery images."
    puts "Sources: #{human_size(source_size)}"
    puts "Optimized full-size images: #{human_size(optimized_size)} in #{GALLERY_DIR}"
    puts "Optimized WebP thumbnails: #{human_size(thumbnail_size)} in #{THUMB_DIR}"
  end
rescue GalleryPreparationError => error
  warn error.message
  exit 1
end
