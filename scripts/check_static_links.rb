#!/usr/bin/env ruby
# frozen_string_literal: true

# Check local href/src/srcset references, fragment identifiers, and curated gallery
# entries in a generated static site.

require "pathname"
require "set"
require "uri"
require "yaml"

class LinkParser
  attr_reader :ids, :links

  def initialize(html)
    @ids = Set.new
    @links = []

    parse(html)
  end

  private

  def parse(html)
    html.scan(/<([a-zA-Z][\w:-]*)([^>]*)>/m) do |tag, attributes|
      tag = tag.downcase
      attributes = parse_attributes(attributes)

      ids << attributes["id"] if present?(attributes["id"])
      ids << attributes["name"] if tag == "a" && present?(attributes["name"])

      %w[href src].each do |attribute|
        value = attributes[attribute]
        links << [attribute, value] if present?(value)
      end

      srcset_urls(attributes["srcset"]).each do |url|
        links << ["srcset", url]
      end
    end
  end

  def parse_attributes(attributes)
    attributes.scan(/([^\s=\/<>'"]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/).each_with_object({}) do |match, parsed|
      name, double_quoted, single_quoted, unquoted = match
      parsed[name.downcase] = double_quoted || single_quoted || unquoted || ""
    end
  end

  def srcset_urls(value)
    return [] unless present?(value)

    value.split(",").filter_map do |candidate|
      candidate.strip.split.first
    end
  end

  def present?(value)
    value && !value.empty?
  end
end

class StaticLinkChecker
  EXTERNAL_SCHEMES = %w[http https mailto tel data].freeze

  attr_reader :build_dir, :repo_root, :errors

  def initialize(build_dir)
    @build_dir = Pathname.new(build_dir).expand_path
    @repo_root = @build_dir.parent
    @parsed_pages = {}
    @errors = []
  end

  def call
    validate_page_links
    validate_home_gallery

    if errors.any?
      puts "Broken local references:"
      errors.each { |error| puts "- #{error}" }
      return 1
    end

    puts "All local href/src/srcset references, fragments, and curated gallery entries resolve."
    0
  end

  private

  attr_reader :parsed_pages

  def validate_page_links
    build_dir.glob("**/*.html").each do |page_path|
      parser = parse_html(page_path)

      parser.links.each do |attribute, url|
        targets = candidate_paths(page_path, url)
        next if targets.empty?

        existing_target = targets.find(&:exist?)

        unless existing_target
          relative_targets = targets.map { |target| relative_to_build(target) }.join(", ")
          errors << "#{relative_to_build(page_path)}: #{attribute}=#{url} -> missing #{relative_targets}"
          next
        end

        validate_fragment(page_path, existing_target, attribute, url)
      end
    end
  end

  def validate_fragment(page_path, target_path, attribute, url)
    fragment = unescape(parse_uri(url).fragment.to_s)
    return if fragment.empty? || target_path.extname != ".html"

    target_parser = parse_html(target_path)
    return if target_parser.ids.include?(fragment)

    errors << "#{relative_to_build(page_path)}: #{attribute}=#{url} -> missing fragment ##{fragment} in #{relative_to_build(target_path)}"
  end

  def parse_html(path)
    path = path.expand_path
    parsed_pages[path.to_s] ||= LinkParser.new(path.read)
  end

  def candidate_paths(page_path, url)
    return [] if external?(url)

    parsed = parse_uri(url)
    path = unescape(parsed.path.to_s)
    return [page_path] if path.empty?

    target = if path.start_with?("/")
      build_dir.join(path.delete_prefix("/"))
    else
      page_path.dirname.join(path)
    end

    if path.end_with?("/")
      [target.join("index.html")]
    elsif !target.extname.empty?
      [target]
    else
      [target, target.join("index.html")]
    end
  end

  def external?(url)
    parsed = parse_uri(url)
    EXTERNAL_SCHEMES.include?(parsed.scheme) || url.start_with?("//")
  end

  def parse_uri(url)
    URI.parse(url)
  rescue URI::InvalidURIError
    URI.parse(URI::DEFAULT_PARSER.escape(url))
  end

  def unescape(value)
    URI::DEFAULT_PARSER.unescape(value)
  end

  def relative_to_build(path)
    path.expand_path.relative_path_from(build_dir).to_s
  rescue ArgumentError
    path.to_s
  end

  def validate_home_gallery
    gallery = gallery_filenames
    home_gallery = home_gallery_filenames
    return if gallery.empty? || home_gallery.empty?

    home_gallery.each do |filename|
      next if gallery.include?(filename)

      errors << "data/home_gallery.yml: #{filename} is not present in data/gallery.yml"
    end
  end

  def gallery_filenames
    gallery_data = repo_root.join("data/gallery.yml")
    return Set.new unless gallery_data.exist?

    YAML.safe_load_file(gallery_data, aliases: true).to_a.filter_map do |entry|
      image = entry["image"].to_s
      File.basename(image) if image.start_with?("galerie/")
    end.to_set
  end

  def home_gallery_filenames
    home_gallery = repo_root.join("data/home_gallery.yml")
    return [] unless home_gallery.exist?

    YAML.safe_load_file(home_gallery, aliases: true).to_a.map(&:to_s)
  end
end

build_dir = ARGV.fetch(0, "build")
exit StaticLinkChecker.new(build_dir).call
