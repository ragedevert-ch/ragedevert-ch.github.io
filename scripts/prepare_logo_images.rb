#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'

ROOT = File.expand_path('..', __dir__)
SOURCE = File.join(ROOT, 'source/assets/images/logo-source.png')
IMAGES_DIR = File.join(ROOT, 'source/assets/images')
PUBLIC_DIR = File.join(ROOT, 'source')
MAGICK = ENV.fetch('MAGICK', 'magick')

DERIVATIVES = [
  {
    output: File.join(IMAGES_DIR, 'logo.webp'),
    size: 1024,
    format: :webp
  },
  {
    output: File.join(IMAGES_DIR, 'favicon.png'),
    size: 64,
    format: :png
  },
  {
    output: File.join(PUBLIC_DIR, 'favicon-32x32.png'),
    size: 32,
    format: :png
  },
  {
    output: File.join(PUBLIC_DIR, 'favicon-16x16.png'),
    size: 16,
    format: :png
  }
].freeze

APPLE_TOUCH_ICON = File.join(PUBLIC_DIR, 'apple-touch-icon.png')
FAVICON_ICO = File.join(PUBLIC_DIR, 'favicon.ico')

def run(*args)
  puts args.join(' ')
  system(*args, exception: true)
end

def transparent_square(output:, size:, format:)
  args = [
    MAGICK,
    SOURCE,
    '-auto-orient',
    '-background', 'none',
    '-alpha', 'on',
    '-trim', '+repage',
    '-filter', 'LanczosSharp',
    '-resize', "#{size}x#{size}",
    '-gravity', 'center',
    '-extent', "#{size}x#{size}",
    '-strip'
  ]

  args.concat(['-define', 'webp:lossless=true', '-quality', '100']) if format == :webp
  args << output

  run(*args)
end

def apple_touch_icon
  run(
    MAGICK,
    SOURCE,
    '-auto-orient',
    '-background', 'none',
    '-alpha', 'on',
    '-trim', '+repage',
    '-filter', 'LanczosSharp',
    '-resize', '164x164',
    '-background', 'white',
    '-gravity', 'center',
    '-extent', '180x180',
    '-alpha', 'remove',
    '-alpha', 'off',
    '-strip',
    APPLE_TOUCH_ICON
  )
end

def favicon_ico
  run(
    MAGICK,
    SOURCE,
    '-auto-orient',
    '-background', 'none',
    '-alpha', 'on',
    '-trim', '+repage',
    '-filter', 'LanczosSharp',
    '(', '-clone', '0', '-resize', '16x16', '-gravity', 'center', '-extent', '16x16', ')',
    '(', '-clone', '0', '-resize', '32x32', '-gravity', 'center', '-extent', '32x32', ')',
    '(', '-clone', '0', '-resize', '48x48', '-gravity', 'center', '-extent', '48x48', ')',
    '-delete', '0',
    '-strip',
    FAVICON_ICO
  )
end

abort "Missing logo source: #{SOURCE}" unless File.exist?(SOURCE)

FileUtils.mkdir_p(IMAGES_DIR)
FileUtils.mkdir_p(PUBLIC_DIR)

DERIVATIVES.each do |derivative|
  transparent_square(**derivative)
end

apple_touch_icon
favicon_ico

puts 'Logo and favicon assets generated.'
