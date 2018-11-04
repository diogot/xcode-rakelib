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
  require 'JSON'
rescue LoadError
  puts 'plist not installed yet!'
end

# -- danger

desc 'Run danger'
task :danger do
  command = 'bundle exec danger local --verbose'
  xcode = Xcode.new
  build_file = File.expand_path('result.json', xcode.default_reports_path)
  sh "#{command} --dangerfile=danger/ValidationDangerfile --danger_id='validation'"
  sh "cat #{xcode.test_report_path} | XCPRETTY_JSON_FILE_OUTPUT=#{build_file} xcpretty -f `xcpretty-json-formatter`"
  ENV['XCODEBUILD_REPORT'] = build_file
  sh "#{command} --dangerfile=danger/TestDangerfile --danger_id='xcodebuild'"
  xcode.tests_results.each do |result|
    ENV['XCODEBUILD_REPORT'] = result[:xcodebuild_report]
    ENV['DANGER_TEST_DESCRIPTION'] = result[:test_description]
    sh "#{command} --dangerfile=danger/TestDangerfile --danger_id='xcodebuild-#{result[:destination]}'"
  end
  sh "#{command} --dangerfile=danger/CompletionDangerfile --danger_id='completion'"
end

namespace 'xcode' do
  desc 'Run unit tests'
  task :tests do
    Xcode.new.run_test
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

  task :bla do
    Xcode.new.last_test_logs_plist
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

    def run_test
      scheme = @config['xcode.tests.scheme']
      destinations = @config['xcode.tests.destinations']
      report_name = @test_report_name

      xcode_args = []
      xcode_args << 'CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= PROVISIONING_PROFILE='
      xcode_args << if @config.workspace_path.nil?
                      "-project #{@config.project_path}"
                    else
                      "-workspace '#{@config.workspace_path}'"
                    end
      xcode_args << "-scheme '#{scheme}'"

      xcode_args_for_build = xcode_args
      xcode_args_for_build << '-destination "generic/platform=iOS Simulator"'
      xcode_args_for_build = xcode_args_for_build.join' '
      xcode(xcode_args: "clean #{xcode_args_for_build}", report_name: "#{report_name}-clean")
      xcode(xcode_args: "analyze build-for-testing -enableCodeCoverage YES #{xcode_args_for_build}", report_name: "#{report_name}-build")

      xcode_args_for_test = xcode_args
      xcode_args_for_test << 'test-without-building'
      xcode_args_for_test << destinations.map { |dest| "-destination '#{dest}'" }.join(' ')
      xcode(xcode_args: xcode_args_for_test.join(' '), report_name: "#{report_name}-tests")
    end

    def test_report_path
      xcode_log_file(report_name: "#{@test_report_name}-build")
    end

    def archive(environment)
      config = @config['xcode.release'][environment]
      bla(scheme: config['scheme'],
          actions: 'clean archive',
          destinations: ['generic/platform=iOS'],
          configuration: config['configuration'],
          report_name: "archive-#{environment}",
          archive_path: archive_path(config['output']))
    end

    def generate_ipa(environment)
      config = @config['xcode.release'][environment]
      export_ipa(archive_path: archive_path(config['output']),
                 export_path: export_path(config['output']),
                 build_plist: create_export_plist(aditional_options: config['sign']),
                 report_name: "export-#{environment}")
    end

    # rubocop:disable Metrics/AbcSize
    def bla(scheme: '',
            actions: '',
            destinations: [],
            configuration: '',
            report_name: '',
            archive_path: '')

      xcode_args = []
      xcode_args << "-configuration '#{configuration}'" unless configuration.to_s.strip.empty?
      xcode_args << 'CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= PROVISIONING_PROFILE=' unless actions.include? 'archive'
      xcode_args << (archive_path.to_s.strip.empty? ? '-enableCodeCoverage YES' : "-archivePath '#{archive_path}'")
      xcode_args << destinations.map { |dest| "-destination '#{dest}'" }.join(' ')
      xcode_args << if @config.workspace_path.nil?
                      "-project #{@config.project_path}"
                    else
                      "-workspace '#{@config.workspace_path}'"
                    end
      xcode_args << "-scheme '#{scheme}'"
      xcode_args << actions
      xcode_args = xcode_args.join ' '

      xcode(xcode_args: xcode_args, report_name: report_name)
    end
    # rubocop:enable Metrics/AbcSize

    def xcode(xcode_args: '',
              report_name: '')
      xcode_log_file = xcode_log_file(report_name: report_name)
      report_file = "#{@reports_path}/#{report_name}.xml"

      Rake.sh "rm -f '#{xcode_log_file}' '#{report_file}'"
      Rake.sh "set -o pipefail && #{xcode_version} xcrun xcodebuild #{xcode_args} | tee '#{xcode_log_file}' | xcpretty --color --no-utf -r junit -o '#{report_file}'"      
    end

    def export_ipa(archive_path: '',
                   export_path: '',
                   build_plist: '',
                   report_name: '')
      xcode_log_file = "#{@artifacts_path}/xcode-#{report_name}.log"
      report_file = "#{@reports_path}/#{report_name}.xml"

      Rake.sh "rm -rf '#{xcode_log_file}' '#{report_file}' #{export_path}"
      Rake.sh "set -o pipefail && #{xcode_version} xcrun xcodebuild -exportArchive -archivePath '#{archive_path}' -exportPath '#{export_path}' -exportOptionsPlist '#{build_plist}' | tee '#{xcode_log_file}' | xcpretty --color --no-utf -r junit -o '#{report_file}'"
    end

    def create_export_plist(aditional_options: {})
      default_plist = { method: 'app-store' }
      plist = default_plist.merge(aditional_options)
      puts plist
      plist_path = "#{@artifacts_path}/export.plist"
      plist.save_plist plist_path
      plist_path
    end

    def tests_results
      find_test_summaries.map do |result|
        parser = TestParser.new(result)

        raw_failed_tests = parser.data.flat_map { |j| j[:tests] }.select { |j| j[:status] == 'Failure' }
        failed_tests = convert_to_json(raw_failed_tests)
        json = {
          tests_failures: failed_tests,
          tests_summary_messages: []
        }
        device = parser.raw_json['RunDestination']['TargetDevice']
        model_name = device['ModelName']
        os_version = device['OperatingSystemVersion']
        formatted_destination = "#{model_name} (#{os_version})"
        destination = "#{model_name}_#{os_version}".delete(' ')

        xcodebuild_tests_path = File.expand_path("test_#{destination}.json", default_reports_path)
        File.open(xcodebuild_tests_path, 'w') { |f| f.write JSON.pretty_generate(json) }
        {
          xcodebuild_report: xcodebuild_tests_path,
          destination: destination,
          test_description: formatted_destination
        }
      end
    end

    def convert_to_json(tests)
      tests.map do |j|
        key = j[:test_group]
        failures = j[:failures].map do |f|
          file_path = f[:file_name]
          file_path += ":#{f[:line_number]}" if f[:line_number]
          {
            file_path: file_path,
            reason: f[:message],
            test_case: j[:name]
          }
        end

        [key, failures]
      end.to_h
    end

    def find_test_summaries
      plist_path = File.expand_path('Info.plist', Dir["#{derived_data_path}/Logs/Test/*xcresult"].max)
      actions = []
      File.open(plist_path, 'r') do |f|
        xml = Plist.parse_xml(f.read)
        actions = xml['Actions'].select { |a| a['SchemeTask'] == 'Action' && a['SchemeCommand'] == 'Test' }
      end

      base_dir = File.dirname(plist_path)
      summaries = actions.map do |a|
        result = a['ActionResult']
        next if result['TestSummaryPath'].to_s.length.zero?

        File.join(base_dir, result['TestSummaryPath'])
      end

      summaries.compact
    end

    def derived_data_path
      build_settings = `#{xcode_version} xcrun xcodebuild -workspace '#{@config.workspace_path}' -scheme '#{@config['xcode.tests.scheme']}' -showBuildSettings`
      result = build_settings.split("\n").find do |c|
        sp = c.split(' = ')
        next if sp.length.zero?

        sp.first.strip == 'BUILT_PRODUCTS_DIR'
      end
      File.expand_path('../../..', result.split(' = ').last)
    end

    def xcode_version
      version = @config['xcode.version']
      xcodes = `mdfind "kMDItemCFBundleIdentifier = 'com.apple.dt.Xcode' && kMDItemVersion = '#{version}'"`.chomp.split("\n")
      raise "Xcode version #{version} not found, If it's already installed update your Spotlight index with 'mdimport /Applications/Xcode*'\n\n" if xcodes.empty?

      # Order by version and get the latest one
      vers = ->(path) { `mdls -name kMDItemVersion -raw "#{path}"` }
      latest_xcode_version = xcodes.sort { |p1, p2| vers.call(p1) <=> vers.call(p2) }.last
      %(DEVELOPER_DIR="#{latest_xcode_version}/Contents/Developer")
    end
  end

  # Based on https://github.com/fastlane/fastl  ane/blob/master/fastlane_core/lib/fastlane_core/test_parser.rb
  class TestParser
    attr_accessor :data

    attr_accessor :file_content

    attr_accessor :raw_json

    def initialize(path)
      path = File.expand_path(path)
      raise("File not found at path '#{path}'") unless File.exist?(path)

      self.file_content = File.read(path)
      self.raw_json = Plist.parse_xml(file_content)
      return if raw_json['FormatVersion'].to_s.length.zero? # maybe that's a useless plist file

      ensure_file_valid!
      parse_content
    end

    private

    def ensure_file_valid!
      format_version = raw_json['FormatVersion']
      supported_versions = ['1.1', '1.2']
      raise("Format version '#{format_version}' is not supported, must be #{supported_versions.join(', ')}") unless supported_versions.include?(format_version)
    end

    # Converts the raw plist test structure into something that's easier to enumerate
    def unfold_tests(data)
      # `data` looks like this
      # => [{"Subtests"=>
      #  [{"Subtests"=>
      #     [{"Subtests"=>
      #        [{"Duration"=>0.4,
      #          "TestIdentifier"=>"Unit/testExample()",
      #          "TestName"=>"testExample()",
      #          "TestObjectClass"=>"IDESchemeActionTestSummary",
      #          "TestStatus"=>"Success",
      #          "TestSummaryGUID"=>"4A24BFED-03E6-4FBE-BC5E-2D80023C06B4"},
      #         {"FailureSummaries"=>
      #           [{"FileName"=>"/Users/krausefx/Developer/themoji/Unit/Unit.swift",
      #             "LineNumber"=>34,
      #             "Message"=>"XCTAssertTrue failed - ",
      #             "PerformanceFailure"=>false}],
      #          "TestIdentifier"=>"Unit/testExample2()",

      tests = []
      data.each do |current_hash|
        if current_hash['Subtests']
          tests += unfold_tests(current_hash['Subtests'])
        end
        if current_hash['TestStatus']
          tests << current_hash
        end
      end
      return tests
    end

    # Convert the Hashes and Arrays in something more useful
    def parse_content
      self.data = self.raw_json["TestableSummaries"].collect do |testable_summary|
        summary_row = {
          project_path: testable_summary["ProjectPath"],
          target_name: testable_summary["TargetName"],
          test_name: testable_summary["TestName"],
          duration: testable_summary["Tests"].map { |current_test| current_test["Duration"] }.inject(:+),
          tests: unfold_tests(testable_summary["Tests"]).collect do |current_test|
            current_row = {
              identifier: current_test["TestIdentifier"],
              test_group: current_test["TestIdentifier"].split("/")[0..-2].join("."),
              name: current_test["TestName"],
              object_class: current_test["TestObjectClass"],
              status: current_test["TestStatus"],
              guid: current_test["TestSummaryGUID"],
              duration: current_test["Duration"]
            }
            if current_test["FailureSummaries"]
              current_row[:failures] = current_test["FailureSummaries"].collect do |current_failure|
                {
                  file_name: current_failure['FileName'],
                  line_number: current_failure['LineNumber'],
                  message: current_failure['Message'],
                  performance_failure: current_failure['PerformanceFailure'],
                  failure_message: "#{current_failure['Message']} (#{current_failure['FileName']}:#{current_failure['LineNumber']})"
                }
              end
            end
            current_row
          end
        }
        summary_row[:number_of_tests] = summary_row[:tests].count
        summary_row[:number_of_failures] = summary_row[:tests].find_all { |a| (a[:failures] || []).count > 0 }.count
        summary_row
      end
      self.data.first[:run_destination_name] = self.raw_json["RunDestination"]["Name"]
      return self.data
    end
  end
end
