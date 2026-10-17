# frozen_string_literal: true

require_relative 'lib/wordcraft/version'

Gem::Specification.new do |spec|
  spec.name = 'wordcraft'
  spec.version = WordCraft::VERSION
  spec.authors = ['Pete Matsyburka']
  spec.email = ['pete@docuseal.com']
  spec.summary = 'Fast DOCX to PDF conversion in Ruby, powered by WordCraft.'
  spec.description = 'Ruby FFI bindings for WordCraft, a pure Rust word processor engine. Ships prebuilt native ' \
                     'libraries for macOS arm64 and Linux (glibc and musl, arm64 and x86_64).'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1.0'

  spec.metadata = {
    'bug_tracker_uri' => 'https://github.com/docusealco/wordcraft-ruby/issues',
    'homepage_uri' => 'https://github.com/docusealco/wordcraft-ruby',
    'source_code_uri' => 'https://github.com/docusealco/wordcraft-ruby',
    'rubygems_mfa_required' => 'true'
  }

  base_files = Dir[
    'lib/**/*.rb',
    'LICENSE',
    'NOTICE',
    'licenses/*',
    'README.md'
  ]

  spec.files =
    if spec.platform.to_s == 'ruby'
      base_files
    else
      platform_dir = case spec.platform.to_s
                     when /x86_64-linux-musl/
                       'x86_64-linux-musl'
                     when /x86_64-linux/
                       'x86_64-linux'
                     when /aarch64-linux-musl/
                       'aarch64-linux-musl'
                     when /aarch64-linux/
                       'aarch64-linux'
                     when /arm64-darwin/
                       'arm64-darwin'
                     end

      if platform_dir
        base_files + Dir["lib/wordcraft/#{platform_dir}/*"]
      else
        base_files
      end
    end

  spec.require_paths = ['lib']

  spec.add_dependency 'ffi', '>= 1.15'
end
