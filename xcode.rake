# frozen_string_literal: true

begin
  require 'plist'
rescue LoadError
  puts 'plist not installed yet!'
end

# -- danger

desc 'Run danger'
task :danger do
  sh 'bundle exec danger'
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

  # Xcode helper class
  class Xcode
    require 'fileutils'
    def initialize
      @config = Config.instance
      @artifacts_path = default_artifacts_path
      @reports_path = default_reports_path
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

    def test_report_name
      'tests'
    end

    def run_test
      xcode scheme: @config['xcode.tests.scheme'],
            actions: 'clean analyze test',
            destinations: @config['xcode.tests.destinations'],
            report_name: test_report_name
    end

    def test_report_path
      xcode_log_file(report_name: test_report_name)
    end

    def archive(environment)
      config = @config['xcode.release'][environment]
      xcode(scheme: config['scheme'],
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
                 build_plist: create_export_plist,
                 report_name: "export-#{environment}")
    end

    # rubocop:disable Metrics/AbcSize
    def xcode(scheme: '',
              actions: '',
              destinations: [],
              configuration: '',
              report_name: '',
              archive_path: '')
      xcode_log_file = xcode_log_file(report_name: report_name)
      report_file = "#{@reports_path}/#{report_name}.xml"

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

      Rake.sh "rm -f '#{xcode_log_file}' '#{report_file}'"
      Rake.sh "set -o pipefail && #{xcode_version} xcrun xcodebuild #{xcode_args} | tee '#{xcode_log_file}' | xcpretty --color --no-utf -r junit -o '#{report_file}'"
    end
    # rubocop:enable Metrics/AbcSize

    def export_ipa(archive_path: '',
                   export_path: '',
                   build_plist: '',
                   report_name: '')
      xcode_log_file = "#{@artifacts_path}/xcode-#{report_name}.log"
      report_file = "#{@reports_path}/#{report_name}.xml"

      Rake.sh "rm -rf '#{xcode_log_file}' '#{report_file}' #{export_path}"
      Rake.sh "set -o pipefail && #{xcode_version} xcrun xcodebuild -exportArchive -archivePath '#{archive_path}' -exportPath '#{export_path}' -exportOptionsPlist '#{build_plist}' | tee '#{xcode_log_file}' | xcpretty --color --no-utf -r junit -o '#{report_file}'"
    end

    def create_export_plist
      plist = { method: 'app-store' }
      plist_path = "#{@artifacts_path}/export.plist"
      plist.save_plist plist_path
      plist_path
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
end