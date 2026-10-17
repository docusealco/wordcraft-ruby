# frozen_string_literal: true

require 'bundler/gem_helper'
require 'fileutils'
require 'rspec/core/rake_task'

RUST_TOOLCHAIN = File.read(File.expand_path('ext/rust-toolchain.toml', __dir__))[/^channel\s*=\s*"([^"]+)"/, 1]

PLATFORMS = {
  'arm64-darwin' => {
    gem_platform: 'arm64-darwin',
    lib_file: 'libwordcraft.dylib'
  },
  'aarch64-linux' => {
    gem_platform: 'aarch64-linux-gnu',
    lib_file: 'libwordcraft.so',
    dockerfile: 'Dockerfile.linux-gnu',
    docker_platform: 'linux/arm64'
  },
  'x86_64-linux' => {
    gem_platform: 'x86_64-linux-gnu',
    lib_file: 'libwordcraft.so',
    dockerfile: 'Dockerfile.linux-gnu',
    docker_platform: 'linux/amd64'
  },
  'aarch64-linux-musl' => {
    gem_platform: 'aarch64-linux-musl',
    lib_file: 'libwordcraft.so',
    dockerfile: 'Dockerfile.linux-musl',
    docker_platform: 'linux/arm64'
  },
  'x86_64-linux-musl' => {
    gem_platform: 'x86_64-linux-musl',
    lib_file: 'libwordcraft.so',
    dockerfile: 'Dockerfile.linux-musl',
    docker_platform: 'linux/amd64'
  }
}.freeze

RSpec::Core::RakeTask.new(:spec)

namespace :wordcraft do
  desc 'Build libwordcraft for a platform (default: this machine) into lib/wordcraft/<platform>'
  task :build, [:platform] do |_t, args|
    platform = args[:platform] || host_platform
    config = PLATFORMS.fetch(platform) { raise ArgumentError, "Unknown platform: #{platform}" }

    config[:dockerfile] ? build_in_docker(platform, config) : build_on_mac(platform, config)
  end

  desc 'Build libwordcraft for all platforms (Linux ones in Docker; run on an arm64 Mac)'
  task :build_all, [:platforms] do |_t, args|
    parse_platforms(args[:platforms]).each do |platform|
      puts "\n==> Building libwordcraft for #{platform}..."
      Rake::Task['wordcraft:build'].execute(Rake::TaskArguments.new([:platform], [platform]))
    end
  end

  desc 'Remove built libraries and build caches'
  task :clean do
    FileUtils.rm_rf('tmp')
    PLATFORMS.each_key { |platform| FileUtils.rm_rf("lib/wordcraft/#{platform}") }
  end
end

namespace :gem do
  desc 'Build platform-specific gems'
  task :build_all, [:platforms] do |_t, args|
    parse_platforms(args[:platforms]).each do |platform|
      Rake::Task['gem:build_platform'].execute(Rake::TaskArguments.new([:platform], [platform]))
    end

    list_built_gems
  end

  desc 'Build gem for a specific platform'
  task :build_platform, [:platform] do |_t, args|
    platform = args[:platform]
    raise ArgumentError, "Unknown platform: #{platform}" unless PLATFORMS.key?(platform)

    build_platform_gem(platform)
  end

  desc 'Build base gem (ruby platform, no native library)'
  task build: :build_base

  task :build_base do
    FileUtils.mkdir_p('pkg')
    sh 'gem build wordcraft.gemspec'
    FileUtils.mv(Dir.glob('wordcraft-*.gem'), 'pkg/')
  end

  desc 'Release all platform gems'
  task release_all: ['gem:build_all'] do
    Dir.glob('pkg/*.gem').each do |gem_file|
      sh "gem push #{gem_file}"
    end
  end
end

namespace :build do
  desc 'Build libraries and gems for all platforms'
  task :all, [:platforms] do |_t, args|
    Rake::Task['wordcraft:build_all'].invoke(args[:platforms])
    Rake::Task['gem:build_base'].invoke
    Rake::Task['gem:build_all'].invoke(args[:platforms])
  end
end

def host_platform
  {
    /arm64-darwin/ => 'arm64-darwin',
    /aarch64-linux-musl/ => 'aarch64-linux-musl',
    /x86_64-linux-musl/ => 'x86_64-linux-musl',
    /aarch64-linux/ => 'aarch64-linux',
    /x86_64-linux/ => 'x86_64-linux'
  }.find { |pattern, _| RUBY_PLATFORM.match?(pattern) }&.last || raise("Unsupported platform: #{RUBY_PLATFORM}")
end

def lib_dest(platform, config)
  dir = File.join('lib', 'wordcraft', platform)
  FileUtils.mkdir_p(dir)

  File.join(dir, config[:lib_file])
end

def build_on_mac(platform, config)
  raise "#{platform} builds on an arm64 Mac (this is #{RUBY_PLATFORM})" unless RUBY_PLATFORM.include?('arm64-darwin')

  target_dir = File.expand_path("tmp/target-#{platform}", __dir__)
  env = {
    'CARGO_TARGET_DIR' => target_dir,
    'CARGO_PROFILE_RELEASE_STRIP' => 'false',
    'MACOSX_DEPLOYMENT_TARGET' => '11.0',
    'RUSTUP_TOOLCHAIN' => RUST_TOOLCHAIN
  }

  sh env, 'cargo', 'build', '--release', '--locked', chdir: File.expand_path('ext', __dir__)

  dest = lib_dest(platform, config)
  FileUtils.cp(File.join(target_dir, 'release', config[:lib_file]), dest)

  sh 'install_name_tool', '-id', "@rpath/#{config[:lib_file]}", dest
  sh 'strip', '-x', dest
  sh 'codesign', '--force', '--sign', '-', dest

  puts "Installed #{dest} (#{(File.size(dest) / 1024.0 / 1024).round(1)} MB)"
end

def build_in_docker(platform, config)
  image = "wordcraft-builder-#{platform}"

  sh 'docker', 'build', '--platform', config[:docker_platform], '-f', config[:dockerfile], '-t', image, '.'

  container_id = `docker create --platform #{config[:docker_platform]} #{image}`.strip

  begin
    dest = lib_dest(platform, config)
    sh 'docker', 'cp', "#{container_id}:/out/#{config[:lib_file]}", dest

    puts "Installed #{dest} (#{(File.size(dest) / 1024.0 / 1024).round(1)} MB)"
  ensure
    sh 'docker', 'rm', container_id
  end
end

def build_platform_gem(platform)
  config = PLATFORMS[platform]
  lib = File.join('lib', 'wordcraft', platform, config[:lib_file])

  raise "#{lib} not found; run `rake wordcraft:build[#{platform}]` first" unless File.exist?(lib)

  FileUtils.mkdir_p('pkg')
  sh "gem build wordcraft.gemspec --platform #{config[:gem_platform]}"
  FileUtils.mv(Dir.glob('wordcraft-*.gem'), 'pkg/')
end

def parse_platforms(platforms_arg)
  if platforms_arg && !platforms_arg.empty?
    platforms_arg.split(',').map(&:strip)
  else
    PLATFORMS.keys
  end
end

def list_built_gems
  puts "\nBuilt gems:"

  Dir.glob('pkg/*.gem').each do |gem|
    puts "  #{File.basename(gem)} (#{(File.size(gem) / 1024.0 / 1024).round(1)} MB)"
  end
end

task default: :spec
