# frozen_string_literal: true

require 'fileutils'

# Path methods
class Path
  # Base path
  def self.base
    Path.of '.'
  end

  # Returns the full path of a file
  # @param file of relative to the project root
  # @param fail_when_missing if true raise an exception if file don't exists
  def self.of(file, fail_when_missing: true)
    path = File.expand_path(file, File.dirname(__FILE__) + '/../')
    raise "File '#{path}' not found" if fail_when_missing && !File.exist?(path)
    path
  end
end

# Configuration
class Config
  require 'yaml'
  include Singleton

  attr_accessor :config

  def initialize
    @config = YAML.load_file Path.of 'rake-config.yml'
  end

  def [](keypath)
    path = keypath.split('.')
    @config.dig(*path)
  end

  def app_name
    self['app_name']
  end

  def workspace_path
    Path.of self['workspace_path']
  end

  def project_path
    Path.of self['project_path']
  end
end

task default: [:help]
task :help do
  sh 'rake -T'
end

at_exit do
  puts '           ¯\_(ツ)_/¯' unless $!.nil? || $!.is_a?(SystemExit) && $!.success?
end
