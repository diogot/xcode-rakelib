# frozen_string_literal: true

require 'fileutils'
require 'yaml'

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

CONFIG = YAML.load_file Path.of 'rake-config.yml'

APP_NAME = CONFIG['app_name']
WORKSPACE_PATH = Path.of CONFIG['workspace_path']
PROJECT_PATH = Path.of CONFIG['project_path']

task default: [:help]
task :help do
  sh 'rake -T'
end

at_exit do
  puts '           ¯\_(ツ)_/¯' unless $!.nil? || $!.is_a?(SystemExit) && $!.success?
end
