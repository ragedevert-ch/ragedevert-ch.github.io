# Middleman Configuration
# https://middlemanapp.com/basics/configure/

require 'fastimage'
require 'json'

activate :livereload

set :layout, :default

set :css_dir, 'assets/css'
set :js_dir, 'assets/js'
set :images_dir, 'assets/images'
set :admin_url, 'https://admin.ragedevert.test'

activate :directory_indexes

ignore 'assets/images/logo-source.png'
ignore 'gribouille/show.html'

GRIBOUILLE_INDEX_LIMIT = 20

# One public page per stored Gribouille (SEO + stable share URLs).
ready do
  Array(app.data.gribouilles).each do |item|
    id = item.respond_to?(:id) ? item.id : item['id']
    next if id.nil? || id.to_s.strip.empty?

    proxy "/gribouille/#{id}/index.html", '/gribouille/show.html', ignore: true
  end
end

configure :build do
  set :admin_url, 'https://admin.ragedevert.ch'

  activate :minify_css
  activate :minify_javascript, ignore: [%r{^/?vendor/photoswipe/}]
  activate :asset_hash, ignore: [
    /^s\//,
    %r{^/?assets/images/gribouille/},
    %r{^/?vendor/photoswipe/},
    %r{^/?apple-touch-icon\.png$},
    %r{^/?favicon-\d+x\d+\.png$},
    %r{^/?favicon\.ico$}
  ]
end

set :site_title, 'Rage de Vert'
set :site_description, 'Association Rage de Vert, agriculture urbaine contractuelle de proximité à Neuchâtel.'
set :site_url, 'https://www.ragedevert.ch'
set :site_email, 'info@ragedevert.ch'
set :signup_url, 'https://membres.ragedevert.ch/new'
set :members_url, 'https://membres.ragedevert.ch/login'
set :instagram_url, 'https://www.instagram.com/ragedevert'
set :facebook_url, 'https://www.facebook.com/ragedevert.ch'
set :linkedin_url, 'https://www.linkedin.com/company/association-rage-de-vert'
set :cloudflare_web_analytics_token, '688c3e4307cf41be893977dbc9d38c02'

helpers do
  def site_title
    config[:site_title]
  end

  def site_description
    config[:site_description]
  end

  def site_url
    config[:site_url]
  end

  def site_email
    config[:site_email]
  end

  def signup_url
    config[:signup_url]
  end

  def members_url
    config[:members_url]
  end

  def admin_url
    config[:admin_url]
  end

  def admin_depots_map_url(depot_ids: nil)
    params = ['style=positron', 'marker_color=287044']
    params << "depot_ids=#{depot_ids}" if depot_ids

    "#{admin_url}/embeds/maps/depots?#{params.join('&amp;')}"
  end

  def instagram_url
    config[:instagram_url]
  end

  def facebook_url
    config[:facebook_url]
  end

  def linkedin_url
    config[:linkedin_url]
  end

  def canonical_path
    path = current_page.path.to_s
    return '/' if path == 'index.html'

    path = path.delete_suffix('.html')
    path = path.delete_suffix('/index')
    return '/' if path.empty?

    "/#{path}/"
  end

  def canonical_url
    "#{site_url}#{canonical_path}"
  end

  def active_path?(path)
    current = current_page.path.to_s
    return current == 'index.html' if path == '/'

    slug = path.delete_prefix('/').delete_suffix('/')
    current == "#{slug}.html" ||
      current == "#{slug}/index.html" ||
      current.start_with?("#{slug}/")
  end

  def active_link_class(path)
    active_path?(path) ? 'is-active' : ''
  end

  def active_link_attributes(path)
    attributes = { class: active_link_class(path) }
    attributes['aria-current'] = 'page' if active_path?(path)
    attributes
  end

  def cloudflare_web_analytics_enabled?
    build? && config[:cloudflare_web_analytics_token].to_s.strip != ''
  end

  def cloudflare_web_analytics_config
    JSON.generate(token: config[:cloudflare_web_analytics_token])
  end

  def page_title
    if (entry = current_gribouille_entry)
      return "#{entry.title} | #{site_title}"
    end

    current_page.data.title ? "#{current_page.data.title} | #{site_title}" : site_title
  end

  def page_description
    if (entry = current_gribouille_entry)
      return gribouille_meta_description(entry)
    end

    current_page.data.description || site_description
  end

  def meta_image_url
    if (entry = current_gribouille_entry) && (image = gribouille_first_image_path(entry))
      return "#{site_url}#{image}"
    end

    absolute_image_url('og-image.jpg')
  end

  def meta_image_dimensions
    if (entry = current_gribouille_entry) && (image = gribouille_first_image_path(entry))
      relative = image.to_s.sub(%r{\A/assets/images/}, '')
      return local_image_size(relative)
    end

    local_image_size('og-image.jpg') || [1200, 630]
  end

  def meta_image_alt
    if (entry = current_gribouille_entry)
      return entry.title.to_s
    end

    'Rage de Vert, paniers de légumes bio à Neuchâtel'
  end

  def og_type
    current_gribouille_entry ? 'article' : 'website'
  end

  # Safe for embedding inside <script type="application/ld+json">.
  def json_ld(payload)
    JSON.generate(payload)
      .gsub('<', "\\u003c")
      .gsub("\u2028", "\\u2028")
      .gsub("\u2029", "\\u2029")
  end

  def absolute_image_url(path)
    "#{site_url}#{image_path(path)}"
  end

  def social_urls
    [instagram_url, facebook_url, linkedin_url]
  end

  def organization_structured_data_hash
    {
      '@type' => 'Organization',
      'name' => site_title,
      'url' => site_url,
      'email' => site_email,
      'logo' => absolute_image_url('logo.webp'),
      'image' => absolute_image_url('og-image.jpg'),
      'sameAs' => social_urls,
      'address' => {
        '@type' => 'PostalAddress',
        'streetAddress' => 'Closel-Bourbon 3',
        'postalCode' => '2075',
        'addressLocality' => 'Thielle-Wavre',
        'addressCountry' => 'CH'
      }
    }
  end

  def page_structured_data_list
    payloads = [
      { '@context' => 'https://schema.org' }.merge(organization_structured_data_hash)
    ]

    if (entry = current_gribouille_entry)
      payloads << gribouille_blog_posting_data(entry)
    elsif current_page.path == 'gribouille.html'
      payloads << gribouille_collection_data
    end

    payloads
  end

  def local_image_tag(path, options = {})
    if (size = local_image_size(path))
      options = { width: size[0], height: size[1] }.merge(options)
    end

    image_tag(path, options)
  end

  def local_image_size(path)
    @local_image_sizes ||= {}
    @local_image_sizes[path] ||= begin
      file_path = File.join(__dir__, 'source', config[:images_dir], path)
      FastImage.size(file_path) if File.exist?(file_path)
    end
  end

  def gallery_image_path(path, _item = nil)
    image_path(path)
  end

  def gallery_image_tag(path, item = nil, options = {})
    if (size = local_image_size(path))
      options = { width: size[0], height: size[1] }.merge(options)
    end

    image_tag(gallery_image_path(path, item), options)
  end

  def gallery_link_label(item, index)
    alt = item.alt.to_s.strip
    return "Voir la photo: #{alt}" unless generic_gallery_alt?(alt)

    date = item.date ? " (#{item.date})" : ''
    "Voir la photo #{index + 1} de la galerie Rage de Vert#{date}"
  end

  def gallery_preview_alt(item, index)
    alt = item.alt.to_s.strip
    return alt unless generic_gallery_alt?(alt)

    "Photo #{index + 1} de la galerie Rage de Vert"
  end

  def generic_gallery_alt?(alt)
    alt.empty? || alt == 'Image de la galerie Rage de Vert'
  end

  def gribouille_index_items
    Array(data.gribouilles).first(GRIBOUILLE_INDEX_LIMIT)
  end

  def gribouille_all_items
    Array(data.gribouilles)
  end

  def gribouille_entry(item)
    return nil unless item

    id = item.respond_to?(:id) ? item.id : item['id']
    gribouille_entry_by_id(id)
  end

  def gribouille_entry_by_id(id)
    entries = data.gribouille_entries
    return nil unless entries && id

    entries[id.to_s] || entries[id] || entries[id.to_s.to_sym]
  end

  def current_gribouille_entry
    match = current_page.path.to_s.match(%r{\Agribouille/(\d+)(?:/index)?\.html\z})
    return nil unless match

    gribouille_entry_by_id(match[1])
  end

  def gribouille_path(entry_or_id)
    id = gribouille_id(entry_or_id)
    "/gribouille/#{id}/"
  end

  def gribouille_url(entry_or_id)
    "#{site_url}#{gribouille_path(entry_or_id)}"
  end

  def gribouille_id(entry_or_id)
    if entry_or_id.respond_to?(:id)
      entry_or_id.id
    elsif entry_or_id.is_a?(Hash)
      entry_or_id['id'] || entry_or_id[:id]
    else
      entry_or_id
    end
  end

  def gribouille_sections_html(entry)
    html = entry.respond_to?(:sections_html) ? entry.sections_html : entry['sections_html']
    # Feed section ids (intro, basket, …) repeat across issues; namespace them so the
    # accordion index and page chrome never emit duplicate document ids.
    namespace_gribouille_fragment_ids(html.to_s, gribouille_id(entry)).html_safe
  end

  def namespace_gribouille_fragment_ids(html, id)
    prefix = "gribouille-#{id}-"
    html
      .gsub(/\bid=(['"])([^'"]+)\1/) { %(id=#{$1}#{prefix}#{$2}#{$1}) }
      .gsub(/\bhref=(['"])#([^'"]+)\1/) { %(href=#{$1}##{prefix}#{$2}#{$1}) }
  end

  def gribouille_file_size(bytes)
    size = bytes.to_i
    return nil unless size.positive?

    kb = (size / 1024.0).round
    return format('%.1f Mo', kb / 1024.0).sub('.0 ', ' ') if kb >= 1024

    "#{kb} Ko"
  end

  def gribouille_meta_description(entry)
    summary = entry.respond_to?(:summary) ? entry.summary : entry['summary']
    text = summary.to_s
      .gsub(/&(?:amp|lt|gt|quot|#39|nbsp);/i, ' ')
      .gsub(/\s+/, ' ')
      .strip
    return site_description if text.empty?

    text.length > 180 ? "#{text[0, 177].sub(/\s+\S*\z/, '')}…" : text
  end

  def gribouille_first_image_path(entry)
    html = entry.respond_to?(:sections_html) ? entry.sections_html : entry['sections_html']
    html.to_s[ /src="(\/assets\/images\/gribouille\/[^\"]+)"/ , 1]
  end

  def gribouille_iso_time(value)
    return if value.nil? || value.to_s.strip.empty?

    Time.parse(value.to_s).iso8601
  rescue ArgumentError, TypeError
    value.to_s
  end

  def gribouille_blog_posting_data(entry)
    data_hash = {
      '@context' => 'https://schema.org',
      '@type' => 'BlogPosting',
      'headline' => entry.title.to_s,
      'description' => gribouille_meta_description(entry),
      'datePublished' => gribouille_iso_time(entry.published_at),
      'dateModified' => gribouille_iso_time(entry.updated_at || entry.published_at),
      'mainEntityOfPage' => {
        '@type' => 'WebPage',
        '@id' => gribouille_url(entry)
      },
      'url' => gribouille_url(entry),
      'isPartOf' => {
        '@type' => 'Blog',
        'name' => 'La Gribouille',
        'url' => "#{site_url}/gribouille/"
      },
      'author' => {
        '@type' => 'Organization',
        'name' => site_title,
        'url' => site_url
      },
      'publisher' => {
        '@type' => 'Organization',
        'name' => site_title,
        'url' => site_url,
        'logo' => {
          '@type' => 'ImageObject',
          'url' => absolute_image_url('logo.webp')
        }
      }
    }

    if (image = gribouille_first_image_path(entry))
      data_hash['image'] = ["#{site_url}#{image}"]
    end

    data_hash
  end

  def gribouille_collection_data
    items = gribouille_all_items.filter_map do |item|
      entry = gribouille_entry(item)
      next unless entry

      {
        '@type' => 'ListItem',
        'position' => nil,
        'url' => gribouille_url(entry),
        'name' => entry.title.to_s
      }
    end
    items.each_with_index { |item, index| item['position'] = index + 1 }

    {
      '@context' => 'https://schema.org',
      '@type' => 'CollectionPage',
      'name' => 'La Gribouille',
      'description' => current_page.data.description || site_description,
      'url' => "#{site_url}/gribouille/",
      'isPartOf' => {
        '@type' => 'WebSite',
        'name' => site_title,
        'url' => site_url
      },
      'mainEntity' => {
        '@type' => 'ItemList',
        'itemListElement' => items
      }
    }
  end

  def gribouille_neighbors(entry)
    items = gribouille_all_items
    index = items.index { |item| gribouille_id(item).to_s == gribouille_id(entry).to_s }
    return [nil, nil] unless index

    newer = index.positive? ? gribouille_entry(items[index - 1]) : nil
    older = gribouille_entry(items[index + 1])
    [newer, older]
  end
end
