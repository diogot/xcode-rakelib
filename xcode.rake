# frozen_string_literal: true

# Xcode-rakelib - https://github.com/diogot/xcode-rakelib
# Copyright (c) 2017 Diogo Tridapalli
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

begin
  require 'plist'
  require 'json'
rescue LoadError
  puts 'plist not installed yet!'
end

# -- Xcode

namespace 'xcode' do
  desc 'Run unit tests'
  task :tests, [:run_danger] do |_t, args|
    run_danger = args[:run_danger]
    destinations = Config.instance['xcode.tests.destinations']
    xcode = Xcode.new
    danger = Danger.new(xcode)

    danger.pre_test if run_danger == 'true'

    begin
      xcode.build_for_test
    rescue e
      raise
    ensure
      danger.build if run_danger == 'true'
    end

    exceptions = []
    destinations.each do |destination|
      xcode.run_test destination
    rescue => e
      exceptions << e
    ensure
      danger.test(destination) if run_danger == 'true'
    end

    raise exceptions.first unless exceptions.first.nil?

    danger.post_test if run_danger == 'true'
  end

  task :clean_artifacts do
    Xcode.new.clean
  end

  task :generate_summary, [:output_path] do |_t, args|
    build_file = args[:output_path]
    sh "cat #{Xcode.new.test_report_path} | XCPRETTY_JSON_FILE_OUTPUT=#{build_file} xcpretty -f `xcpretty-json-formatter`"
  end

  desc 'Release'
  task :release, [:env] => %i[archive generate_ipa]

  task :archive, [:env] do |_t, args|
    env = args[:env].to_s
    Xcode.new.archive env
  end

  task :generate_ipa, [:env] do |_t, args|
    env = args[:env].to_s
    Xcode.new.generate_ipa env
  end

  task :upload, [:env] do |_t, args|
    env = args[:env].to_s
    Xcode.new.upload env
  end

  # Xcode helper class
  class Xcode
    require 'fileutils'
    def initialize
      @config = Config.instance
      @artifacts_path = default_artifacts_path
      @reports_path = default_reports_path
      @test_report_name = 'tests'
    end

    # Paths

    def clean
      Rake.sh "rm -rf '#{@artifacts_path}' '#{@reports_path}'"
    end

    def default_artifacts_path
      artifacts_path = ENV['ARTIFACTS_PATH'] || Path.of(@config['xcode.build_path'], fail_when_missing: false)
      File.expand_path artifacts_path
      FileUtils.mkdir_p artifacts_path

      artifacts_path
    end

    def default_reports_path
      reports_path = ENV['TEST_REPORTS_PATH'] || Path.of(@config['xcode.reports_path'], fail_when_missing: false)
      File.expand_path reports_path
      FileUtils.mkdir_p reports_path

      reports_path
    end

    def archive_path(filename)
      "#{@artifacts_path}/#{filename}.xcarchive"
    end

    def export_path(filename)
      "#{@artifacts_path}/#{filename}-ipa"
    end

    def xcode_log_file(report_name: '')
      "#{@artifacts_path}/xcode-#{report_name}.log"
    end

    # Xcode

    def build_for_test
      scheme = @config['xcode.tests.scheme']
      report_name = @test_report_name

      xcode_args = ['CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= PROVISIONING_PROFILE=']
      xcode_args << project_or_workspace
      xcode_args << "-scheme '#{scheme}'"
      xcode_args << '-destination "generic/platform=iOS Simulator"'

      xcode(xcode_args: ['clean'] + xcode_args, report_name: "#{report_name}-clean")

      xcode_args_for_build = ['analyze']
      xcode_args_for_build << 'build-for-testing'
      xcode_args_for_build << '-enableCodeCoverage YES'
      xcode_args_for_build << 'build-for-testing'

      xcode(xcode_args: xcode_args_for_build + xcode_args, report_name: "#{report_name}-build")
    end

    def run_test(destination)
      scheme = @config['xcode.tests.scheme']
      report_name = @test_report_name

      xcode_args = ['CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= PROVISIONING_PROFILE=']
      xcode_args << project_or_workspace
      xcode_args << "-scheme '#{scheme}'"

      xcode_args_for_test = ['test-without-building'] + xcode_args
      xcode_args_for_test << "-destination '#{destination}'"
      xcode(xcode_args: xcode_args_for_test, report_name: "#{report_name}-#{string_for_destination(destination)}")
    end

    def archive(environment)
      config = @config['xcode.release'][environment]

      configuration = config['configuration']
      xcode_args = [project_or_workspace]
      xcode_args << "-configuration '#{configuration}'" unless configuration.to_s.strip.empty?
      xcode_args << "-archivePath '#{archive_path(config['output'])}'"
      xcode_args << "-destination 'generic/platform=iOS'"
      xcode_args << "-scheme '#{config['scheme']}'"
      xcode_args << 'clean archive'
      xcode(xcode_args: xcode_args, report_name: "archive-#{environment}")
    end

    def generate_ipa(environment)
      config = @config['xcode.release'][environment]

      export_path = export_path(config['output'])
      xcode_args = []
      xcode_args << '-exportArchive'
      xcode_args << "-archivePath '#{archive_path(config['output'])}'"
      xcode_args << "-exportPath '#{export_path}'"
      xcode_args << "-exportOptionsPlist '#{create_export_plist(aditional_options: config['sign'])}'"
      Rake.sh "rm -rf '#{export_path}'"
      xcode(xcode_args: xcode_args, report_name: "export-#{environment}")
    end

    def xcode(xcode_args: [], report_name: '')
      xcode_log_file = xcode_log_file(report_name: report_name)
      report_file = "#{@reports_path}/#{report_name}.xml"
      results_file = xcode_results_path(report_name: report_name)
      xcode_args << "-resultBundlePath '#{results_file}'"
      xcode_args = xcode_args.join ' '

      Rake.sh "rm -rf '#{xcode_log_file}' '#{report_file}' '#{results_file}'"
      Rake.sh "set -o pipefail && #{xcode_version} xcrun xcodebuild #{xcode_args} | tee '#{xcode_log_file}' | xcpretty --color --no-utf -r junit -o '#{report_file}'"
    end

    def upload(environment)
      config = @config['xcode.release'][environment]
      ipa = "#{export_path(config['output'])}/#{config['scheme']}.ipa"
      pass = ENV['APP_STORE_PASS'] ? ' -p @env:APP_STORE_PASS' : ''
      Rake.sh "#{xcode_version} xcrun altool --upload-app -f '#{ipa}' -u #{config['app_store_account']} #{pass}"
    end

    def project_or_workspace
      if @config.workspace_path.nil?
        "-project '#{@config.project_path}'"
      else
        "-workspace '#{@config.workspace_path}'"
      end
    end

    def string_for_destination(destination)
      # rubocop:disable Style/Semicolon
      elements = destination.split(',').map { |h| h1, h2 = h.split('='); { h1 => h2 } }.reduce(:merge)
      # rubocop:enable Style/Semicolon
      os = elements['OS']
      device = elements['name']
      name = os.to_s.empty? ? '' : os
      unless device.to_s.empty?
        name += '_' unless name.to_s.empty?
        name += device
      end
      name.gsub(/\s+/, '')
    end

    def test_report_path
      xcode_log_file(report_name: "#{@test_report_name}-build")
    end

    def xcode_results_path(report_name: '')
      "#{@reports_path}/#{report_name}.xcresult"
    end

    def xcode_results(destination: '')
      xcode_results_path(report_name: "#{@test_report_name}-#{string_for_destination(destination)}")
    end

    def create_export_plist(aditional_options: {})
      default_plist = { method: 'app-store' }
      plist = default_plist.merge(aditional_options)
      puts plist
      plist_path = "#{@artifacts_path}/export.plist"
      plist.save_plist plist_path
      plist_path
    end

    def test_results(destination)
      {
        xcode_results: xcode_results(destination: destination)
      }
    end

    def xcode_version
      version = @config['xcode.version']
      latest_xcode_version = installed_xcodes.select { |xcode| Gem::Dependency.new('', "~> #{version}").match?('', fetch_version(xcode)) }.max { |a, b| fetch_version(a) <=> fetch_version(b) }
      raise "Xcode version #{version} not found,\n\n" if latest_xcode_version.nil?

      %(DEVELOPER_DIR="#{latest_xcode_version}/Contents/Developer")
    end

    def installed_xcodes
      result = `mdfind "kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'" 2>/dev/null`.split("\n")
      if result.empty?
        result = `find /Applications -name '*.app' -type d -maxdepth 1 -exec sh -c \
        'if [ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
        "{}/Contents/Info.plist" 2>/dev/null)" == "com.apple.dt.Xcode" ]; then echo "{}"; fi' ';'`.split("\n")
      end
      result
    end

    def fetch_version(path)
      output = `/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" #{path}/Contents/Info.plist`
      return '0.0' if output.nil? || output.empty?

      output.split("\n").first
    end
  end

  # Danger helper class
  class Danger
    def initialize(xcode)
      @xcode = xcode
      @config = Config.instance
      @danger = 'bundle exec danger --verbose'
    end

    def pre_test
      dangerfile = @config['danger.dangerfile_paths.pre_test']
      return if dangerfile.nil?

      Rake.sh "#{@danger} --dangerfile=#{dangerfile} --danger_id='pre_test'"
    end

    def build
      dangerfile = @config['danger.dangerfile_paths.test']
      return if dangerfile.nil?

      ENV['XCODE_RESULTS'] = @xcode.xcode_results_path(report_name: 'tests-build')
      Rake.sh "#{@danger} --dangerfile=#{dangerfile} --danger_id='xcodebuild'"
    end

    def test(destination)
      dangerfile = @config['danger.dangerfile_paths.test']
      return if dangerfile.nil?

      results = @xcode.test_results(destination)
      ENV['XCODE_RESULTS'] = results[:xcode_results]
      Rake.sh "#{@danger} --dangerfile=#{dangerfile} --danger_id='xcodebuild-#{destination}'"
    end

    def post_test
      dangerfile = @config['danger.dangerfile_paths.post_test']
      return if dangerfile.nil?

      Rake.sh "#{@danger} --dangerfile=#{dangerfile} --danger_id='post_test'"
    end
  end
end
