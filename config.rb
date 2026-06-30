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

configure :build do
  set :admin_url, 'https://admin.ragedevert.ch'

  activate :minify_css
  activate :minify_javascript, ignore: [%r{^/?vendor/photoswipe/}]
  activate :asset_hash, ignore: [
    /^s\//,
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
set :members_url, 'https://membres.ragedevert.ch'
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
    return '/' if current_page.path == 'index.html'

    "/#{current_page.path.delete_suffix('.html')}/"
  end

  def canonical_url
    "#{site_url}#{canonical_path}"
  end

  def active_path?(path)
    current = current_page.path
    return current == 'index.html' if path == '/'

    slug = path.delete_prefix('/').delete_suffix('/')
    current == "#{slug}.html"
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
    current_page.data.title ? "#{current_page.data.title} | #{site_title}" : site_title
  end

  def page_description
    current_page.data.description || site_description
  end

  def meta_image_url
    absolute_image_url('og-image.jpg')
  end

  def meta_image_alt
    'Rage de Vert, paniers de légumes bio à Neuchâtel'
  end

  def absolute_image_url(path)
    "#{site_url}#{image_path(path)}"
  end

  def social_urls
    [instagram_url, facebook_url, linkedin_url]
  end

  def organization_structured_data
    JSON.generate(
      '@context' => 'https://schema.org',
      '@type' => 'Organization',
      'name' => site_title,
      'url' => site_url,
      'email' => "mailto:#{site_email}",
      'logo' => absolute_image_url('logo.webp'),
      'image' => meta_image_url,
      'sameAs' => social_urls,
      'address' => {
        '@type' => 'PostalAddress',
        'streetAddress' => 'Closel-Bourbon 3',
        'postalCode' => '2075',
        'addressLocality' => 'Thielle-Wavre',
        'addressCountry' => 'CH'
      }
    )
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
end
