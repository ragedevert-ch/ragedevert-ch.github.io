#!/usr/bin/env ruby
# frozen_string_literal: true

# Sync public Gribouille newsletters from the CSA Admin Atom feed into this
# static site:
# - fetches https://membres.ragedevert.ch/newsletters.atom?template_id=9
# - downloads images and file attachments immediately (short-lived URLs)
# - rewrites HTML image src to local paths
# - writes data/gribouille_entries/<id>.yml + data/gribouilles.yml
#
# Usage:
#   ruby scripts/sync_gribouilles.rb
#   ruby scripts/sync_gribouilles.rb --feed-url URL
#   ruby scripts/sync_gribouilles.rb --dry-run
#   ruby scripts/sync_gribouilles.rb --force
#
# Env:
#   GRIBOUILLE_FEED_URL — default feed URL override
#   MAGICK — ImageMagick binary (default: magick)

require "cgi"
require "date"
require "fileutils"
require "net/http"
require "open3"
require "optparse"
require "rexml/document"
require "set"
require "tempfile"
require "time"
require "uri"
require "yaml"

ROOT = File.expand_path("..", __dir__)
DATA_DIR = File.join(ROOT, "data")
ENTRIES_DIR = File.join(DATA_DIR, "gribouille_entries")
INDEX_PATH = File.join(DATA_DIR, "gribouilles.yml")
IMAGES_ROOT = File.join(ROOT, "source/assets/images/gribouille")
DOCS_ROOT = File.join(ROOT, "source/s/gribouille")
DEFAULT_FEED_URL = "https://membres.ragedevert.ch/newsletters.atom?template_id=9"
ATOM_NS = "http://www.w3.org/2005/Atom"
CSA_NS = "https://csa-admin.org/atom"
IMAGE_MAX_DIMENSION = 1_200
IMAGE_QUALITY = 80
MAGICK = ENV.fetch("MAGICK", "magick")
USER_AGENT = "RageDeVertGribouilleSync/1.0 (+https://www.ragedevert.ch)"
ALLOWED_DOWNLOAD_HOSTS = %w[
  membres.ragedevert.ch
  membres.ragedevert.test
  admin.ragedevert.ch
  admin.ragedevert.test
].freeze
ALLOWED_IMAGE_TYPES = %w[
  image/jpeg
  image/png
  image/webp
  image/gif
].freeze
ALLOWED_IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .webp .gif].freeze
ALLOWED_ATTACHMENT_TYPES = %w[
  application/pdf
].freeze
ALLOWED_ATTACHMENT_EXTENSIONS = %w[.pdf].freeze
MAX_DOWNLOAD_BYTES = 25 * 1024 * 1024

class SyncError < StandardError; end

Options = Struct.new(:feed_url, :dry_run, :force, :allowed_hosts, keyword_init: true)

def parse_options(argv)
  options = Options.new(
    feed_url: ENV.fetch("GRIBOUILLE_FEED_URL", DEFAULT_FEED_URL),
    dry_run: false,
    force: false,
    allowed_hosts: nil
  )

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: ruby scripts/sync_gribouilles.rb [options]"
    opts.on("--feed-url URL", "Atom feed URL") { |value| options.feed_url = value }
    opts.on("--dry-run", "Fetch and plan without writing files") { options.dry_run = true }
    opts.on("--force", "Re-download every entry in the feed window") { options.force = true }
  end
  parser.parse!(argv)

  feed_uri = URI.parse(options.feed_url)
  raise SyncError, "Feed URL must be http(s): #{options.feed_url}" unless %w[http https].include?(feed_uri.scheme)
  raise SyncError, "Feed URL is missing a host: #{options.feed_url}" if feed_uri.host.to_s.empty?

  options.allowed_hosts = (ALLOWED_DOWNLOAD_HOSTS + [feed_uri.host.downcase]).uniq
  options
end

def log(message)
  warn(message)
end

def private_or_local_host?(host)
  return true if host.nil? || host.empty?
  return true if host == "localhost" || host.end_with?(".localhost")
  return true if host == "0.0.0.0"

  # Block literal IPs in private/link-local/loopback ranges (SSRF guard).
  if host.match?(/\A\d{1,3}(?:\.\d{1,3}){3}\z/)
    parts = host.split(".").map(&:to_i)
    return true if parts[0] == 10
    return true if parts[0] == 127
    return true if parts[0] == 0
    return true if parts[0] == 169 && parts[1] == 254
    return true if parts[0] == 172 && (16..31).cover?(parts[1])
    return true if parts[0] == 192 && parts[1] == 168
  end

  false
end

def assert_fetchable_uri!(uri, allowed_hosts:, require_allowlist:)
  uri = URI.parse(uri.to_s) unless uri.is_a?(URI)
  raise SyncError, "Only http(s) URLs are supported: #{uri}" unless %w[http https].include?(uri.scheme)
  raise SyncError, "URL is missing a host: #{uri}" if uri.host.to_s.empty?

  host = uri.host.downcase
  raise SyncError, "Refusing private/local host #{host}" if private_or_local_host?(host)

  if require_allowlist && !allowed_hosts.map(&:downcase).include?(host)
    raise SyncError, "Refusing download from untrusted host #{host} (allowed: #{allowed_hosts.join(', ')})"
  end

  # After a trusted hop, only follow https redirects (Active Storage may land on object storage).
  if !require_allowlist && uri.scheme != "https"
    raise SyncError, "Refusing non-https redirect to #{uri}"
  end

  uri
end

def fetch_uri(uri, allowed_hosts:, limit: 8, require_allowlist: true)
  raise SyncError, "Too many redirects for #{uri}" if limit <= 0

  uri = assert_fetchable_uri!(uri, allowed_hosts: allowed_hosts, require_allowlist: require_allowlist)

  response = Net::HTTP.start(
    uri.host,
    uri.port,
    use_ssl: uri.scheme == "https",
    open_timeout: 30,
    read_timeout: 120
  ) do |http|
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = USER_AGENT
    request["Accept"] = "*/*"
    http.request(request)
  end

  case response
  when Net::HTTPSuccess
    body = response.body
    body = body.dup if body.frozen?
    body.force_encoding(Encoding::BINARY)
    if body.bytesize > MAX_DOWNLOAD_BYTES
      raise SyncError, "Download exceeds #{MAX_DOWNLOAD_BYTES} bytes for #{uri}"
    end

    {
      body: body,
      content_type: response["Content-Type"].to_s,
      final_uri: uri
    }
  when Net::HTTPRedirection
    location = response["Location"]
    raise SyncError, "Redirect without Location from #{uri}" if location.nil? || location.empty?

    # Initial URL must be allowlisted; Active Storage may then redirect to object storage.
    fetch_uri(
      URI.join(uri.to_s, location),
      allowed_hosts: allowed_hosts,
      limit: limit - 1,
      require_allowlist: false
    )
  else
    raise SyncError, "HTTP #{response.code} for #{uri}"
  end
end

def text_at(element, xpath)
  return "" unless element

  node = REXML::XPath.first(element, xpath, "a" => ATOM_NS, "csa" => CSA_NS)
  return "" unless node

  node.text.to_s.strip
end

def elements_at(element, xpath)
  REXML::XPath.match(element, xpath, "a" => ATOM_NS, "csa" => CSA_NS)
end

def parse_feed(xml)
  document = REXML::Document.new(xml)
  root = document.root
  raise SyncError, "Invalid Atom feed: missing root" unless root

  entries = elements_at(root, "a:entry").map do |entry|
    atom_id = text_at(entry, "a:id")
    newsletter_id = atom_id[/:newsletter\/(\d+)\z/, 1]
    raise SyncError, "Cannot parse newsletter id from #{atom_id.inspect}" unless newsletter_id

    content_node = REXML::XPath.first(entry, "a:content", "a" => ATOM_NS, "csa" => CSA_NS)
    content_html = ""
    if content_node
      content_html = content_node.cdatas.map(&:to_s).join
      if content_html.empty?
        content_html = content_node.texts.map { |text| text.respond_to?(:value) ? text.value : text.to_s }.join
      end
      content_html = content_node.text.to_s if content_html.empty?
    end

    enclosures = elements_at(entry, "a:link[@rel='enclosure']").map do |link|
      {
        "title" => link.attributes["title"].to_s,
        "type" => link.attributes["type"].to_s,
        "length" => link.attributes["length"].to_s.to_i,
        "href" => link.attributes["href"].to_s
      }
    end

    {
      "id" => newsletter_id.to_i,
      "atom_id" => atom_id,
      "title" => text_at(entry, "a:title"),
      "published_at" => text_at(entry, "a:published"),
      "updated_at" => text_at(entry, "a:updated"),
      "summary" => text_at(entry, "a:summary"),
      "content_digest" => text_at(entry, "csa:content_digest"),
      "sections_html" => content_html,
      "remote_attachments" => enclosures
    }
  end

  raise SyncError, "Atom feed contains no entries" if entries.empty?

  entries
end

def load_entry(id)
  path = File.join(ENTRIES_DIR, "#{id}.yml")
  return nil unless File.exist?(path)

  YAML.safe_load_file(path, permitted_classes: [Date, Time])
rescue Psych::SyntaxError => error
  raise SyncError, "Invalid YAML in #{path}: #{error.message}"
end

def entry_up_to_date?(existing, remote, force:)
  return false if force
  return false if existing.nil?
  return false if existing["content_digest"].to_s.empty? || remote["content_digest"].to_s.empty?

  existing["content_digest"] == remote["content_digest"] &&
    existing["title"] == remote["title"] &&
    existing["published_at"] == remote["published_at"]
end

def sanitize_filename(name, fallback:)
  base = name.to_s.strip
  base = fallback if base.empty?
  base = File.basename(base)
  base = CGI.unescape(base)
  base = base.gsub(/[^\w.\-]+/u, "_")
  base = base.gsub(/_+/u, "_")
  base = base.gsub(/\A[._]+|[._]+\z/u, "")
  base = fallback if base.empty?
  base
end

def extension_for(content_type, filename)
  ext = File.extname(filename).downcase
  return ext unless ext.empty?

  case content_type.to_s.downcase
  when %r{\Aimage/jpeg} then ".jpg"
  when %r{\Aimage/png} then ".png"
  when %r{\Aimage/webp} then ".webp"
  when %r{\Aimage/gif} then ".gif"
  when %r{\Aapplication/pdf} then ".pdf"
  else
    ""
  end
end

def unique_name(used, desired)
  return desired if used.add?(desired)

  stem = desired.sub(/(\.[^.]+)\z/, "")
  ext = Regexp.last_match(1).to_s
  index = 2
  loop do
    candidate = "#{stem}-#{index}#{ext}"
    return candidate if used.add?(candidate)

    index += 1
  end
end

def extract_img_srcs(html)
  html.to_s.scan(/<img\b[^>]*\bsrc=(["'])(.*?)\1/im).map { |_, src| src }
end

def rewrite_img_srcs(html, mapping)
  html.to_s.gsub(/<img\b[^>]*\bsrc=(["'])(.*?)\1/im) do |match|
    quote = Regexp.last_match(1)
    src = Regexp.last_match(2)
    local = mapping[src]
    next match unless local

    match.sub("src=#{quote}#{src}#{quote}", "src=#{quote}#{local}#{quote}")
  end
end

def magick_available?
  @magick_available ||= begin
    _stdout, _stderr, status = Open3.capture3(MAGICK, "-version")
    status.success?
  end
end

def optimize_image!(path)
  return unless magick_available?
  return unless File.file?(path)

  ext = File.extname(path).downcase
  return unless %w[.jpg .jpeg .png .webp].include?(ext)

  Tempfile.create(["gribouille-opt", ext]) do |temp|
    temp.close
    command = [
      MAGICK,
      path,
      "-auto-orient",
      "-resize", "#{IMAGE_MAX_DIMENSION}x#{IMAGE_MAX_DIMENSION}>",
      "-strip"
    ]
    command += ["-quality", IMAGE_QUALITY.to_s] if %w[.jpg .jpeg .webp].include?(ext)
    command << temp.path

    _stdout, stderr, status = Open3.capture3(*command)
    raise SyncError, "ImageMagick failed for #{path}: #{stderr}" unless status.success?

    FileUtils.mv(temp.path, path)
  end
end

def media_type(content_type)
  content_type.to_s.split(";", 2).first.to_s.strip.downcase
end

def assert_image_type!(content_type, filename)
  type = media_type(content_type)
  ext = File.extname(filename.to_s).downcase
  allowed_type = ALLOWED_IMAGE_TYPES.include?(type)
  allowed_ext = ALLOWED_IMAGE_EXTENSIONS.include?(ext)
  return if allowed_type || (type.empty? && allowed_ext)

  raise SyncError, "Unsupported image type #{type.inspect} (#{filename})"
end

def assert_attachment_type!(content_type, filename, declared_type: nil)
  type = media_type(content_type)
  declared = media_type(declared_type)
  ext = File.extname(filename.to_s).downcase
  type = declared if type.empty? && !declared.empty?

  allowed_type = ALLOWED_ATTACHMENT_TYPES.include?(type)
  allowed_ext = ALLOWED_ATTACHMENT_EXTENSIONS.include?(ext)
  return if allowed_type || (type.empty? && allowed_ext)

  raise SyncError, "Unsupported attachment type #{type.inspect} (#{filename})"
end

def download_binary(url, allowed_hosts:)
  result = fetch_uri(url, allowed_hosts: allowed_hosts)
  raise SyncError, "Empty body for #{url}" if result[:body].nil? || result[:body].empty?

  result
end

def write_atomic(path, content)
  dir = File.dirname(path)
  FileUtils.mkdir_p(dir)
  basename = File.basename(path)
  Tempfile.create([basename, ".tmp"], dir) do |temp|
    temp.binmode
    temp.write(content)
    temp.flush
    temp.fsync
    FileUtils.mv(temp.path, path)
  end
  File.chmod(0o644, path)
end

def yaml_dump(data)
  payload = data.is_a?(Hash) ? data.transform_keys(&:to_s) : data
  yaml = YAML.dump(payload)
  yaml = yaml.sub(/\A---\n/, "")
  "# Synced from CSA Admin Atom feed — do not hand-edit\n---\n#{yaml}"
end

def materialize_entry(remote, dry_run:, allowed_hosts:)
  id = remote["id"]
  used_image_names = Set.new
  used_doc_names = Set.new
  image_map = {}
  attachments = []

  img_srcs = extract_img_srcs(remote["sections_html"]).uniq
  image_dir = File.join(IMAGES_ROOT, id.to_s)
  docs_dir = File.join(DOCS_ROOT, id.to_s)

  img_srcs.each_with_index do |src, index|
    raise SyncError, "Blank image src in newsletter #{id}" if src.to_s.strip.empty?

    downloaded = download_binary(src, allowed_hosts: allowed_hosts)
    original_name = File.basename(URI.parse(src).path.to_s)
    original_name = "image-#{index + 1}" if original_name.empty?
    assert_image_type!(downloaded[:content_type], original_name)
    ext = extension_for(downloaded[:content_type], original_name)
    desired = sanitize_filename(original_name, fallback: "image-#{index + 1}#{ext}")
    desired = "#{desired}#{ext}" if File.extname(desired).empty? && !ext.empty?
    filename = unique_name(used_image_names, desired)
    local_path = "/assets/images/gribouille/#{id}/#{filename}"
    image_map[src] = local_path

    next if dry_run

    FileUtils.mkdir_p(image_dir)
    absolute = File.join(image_dir, filename)
    write_atomic(absolute, downloaded[:body])
    optimize_image!(absolute)
  end

  remote["remote_attachments"].each_with_index do |enclosure, index|
    href = enclosure["href"].to_s
    raise SyncError, "Blank enclosure href in newsletter #{id}" if href.empty?

    downloaded = download_binary(href, allowed_hosts: allowed_hosts)
    original_name = enclosure["title"].to_s
    original_name = File.basename(URI.parse(href).path.to_s) if original_name.empty?
    assert_attachment_type!(downloaded[:content_type], original_name, declared_type: enclosure["type"])
    ext = extension_for(downloaded[:content_type], original_name)
    desired = sanitize_filename(original_name, fallback: "piece-jointe-#{index + 1}#{ext}")
    desired = "#{desired}#{ext}" if File.extname(desired).empty? && !ext.empty?
    filename = unique_name(used_doc_names, desired)
    public_path = "/s/gribouille/#{id}/#{filename}"
    stored_type = media_type(enclosure["type"])
    stored_type = media_type(downloaded[:content_type]) if stored_type.empty?
    stored_type = "application/pdf" if stored_type.empty?

    attachments << {
      "title" => enclosure["title"].to_s.empty? ? filename : enclosure["title"],
      "path" => public_path,
      "type" => stored_type,
      "bytes" => enclosure["length"].positive? ? enclosure["length"] : downloaded[:body].bytesize
    }

    next if dry_run

    FileUtils.mkdir_p(docs_dir)
    absolute = File.join(docs_dir, filename)
    write_atomic(absolute, downloaded[:body])
  end

  sections_html = rewrite_img_srcs(remote["sections_html"], image_map)
  leftover = extract_img_srcs(sections_html).grep(%r{\Ahttps?://}i)
  raise SyncError, "Unrewritten remote images remain in newsletter #{id}: #{leftover.join(', ')}" if leftover.any?

  unless dry_run
    if Dir.exist?(image_dir)
      keep_images = image_map.values.map { |path| File.basename(path) }.to_set
      Dir.glob(File.join(image_dir, "*")).each do |path|
        next unless File.file?(path)
        next if keep_images.include?(File.basename(path))

        FileUtils.rm_f(path)
      end
      FileUtils.rm_rf(image_dir) if keep_images.empty?
    end

    if Dir.exist?(docs_dir)
      keep_docs = attachments.map { |item| File.basename(item["path"]) }.to_set
      Dir.glob(File.join(docs_dir, "*")).each do |path|
        next unless File.file?(path)
        next if keep_docs.include?(File.basename(path))

        FileUtils.rm_f(path)
      end
      FileUtils.rm_rf(docs_dir) if keep_docs.empty?
    end
  end

  {
    "id" => id,
    "atom_id" => remote["atom_id"],
    "title" => remote["title"],
    "published_at" => remote["published_at"],
    "updated_at" => remote["updated_at"],
    "content_digest" => remote["content_digest"],
    "summary" => remote["summary"],
    "sections_html" => sections_html,
    "attachments" => attachments
  }
end

def write_entry(entry)
  path = File.join(ENTRIES_DIR, "#{entry['id']}.yml")
  write_atomic(path, yaml_dump(entry))
end

def rebuild_index!(touched_entries)
  by_id = {}

  Dir.glob(File.join(ENTRIES_DIR, "*.yml")).each do |path|
    entry = YAML.safe_load_file(path, permitted_classes: [Date, Time])
    next unless entry.is_a?(Hash) && entry["id"]

    by_id[entry["id"].to_i] = entry
  end

  touched_entries.each do |entry|
    by_id[entry["id"].to_i] = entry
  end

  index = by_id.values.sort_by do |entry|
    begin
      Time.parse(entry["published_at"].to_s)
    rescue ArgumentError, TypeError
      Time.at(0)
    end
  end.reverse.map do |entry|
    {
      "id" => entry["id"],
      "title" => entry["title"],
      "published_at" => entry["published_at"],
      "updated_at" => entry["updated_at"],
      "content_digest" => entry["content_digest"],
      "summary" => entry["summary"],
      "entry" => "gribouille_entries/#{entry['id']}.yml"
    }
  end

  write_atomic(INDEX_PATH, yaml_dump(index))
  index
end

def main(argv)
  options = parse_options(argv)
  log("Fetching #{options.feed_url}")
  log("Allowed download hosts: #{options.allowed_hosts.join(', ')}")
  feed = fetch_uri(options.feed_url, allowed_hosts: options.allowed_hosts)
  remotes = parse_feed(feed[:body])
  log("Feed entries: #{remotes.size}")

  FileUtils.mkdir_p(ENTRIES_DIR) unless options.dry_run

  changed = []
  skipped = 0

  remotes.each do |remote|
    existing = load_entry(remote["id"])
    if entry_up_to_date?(existing, remote, force: options.force)
      skipped += 1
      log("Skip ##{remote['id']} (up to date)")
      next
    end

    log("#{options.dry_run ? 'Plan' : 'Sync'} ##{remote['id']} — #{remote['title']}")
    entry = materialize_entry(remote, dry_run: options.dry_run, allowed_hosts: options.allowed_hosts)
    write_entry(entry) unless options.dry_run
    changed << entry
  end

  unless options.dry_run
    rebuild_index!(changed)
  end

  if changed.empty?
    log("No changes (#{skipped} up to date).")
  else
    log("#{options.dry_run ? 'Would update' : 'Updated'} #{changed.size} issue(s); skipped #{skipped}.")
  end
end

main(ARGV) if $PROGRAM_NAME == __FILE__
