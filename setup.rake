# frozen_string_literal: true

# -- project setup

desc 'Install/update and configure project'
task setup: %i[setup:install setup:dependencies]

namespace 'setup' do
  def disabled?(config)
    config.nil? || !config['enabled']
  end

  # -- Install

  task install: %i[bundler brew]

  desc 'Bundle install'
  task :bundler do
    bundler = Config.instance['setup.bundler']
    next if disabled? bundler
    bundler_path = ENV['BUNDLER_PATH'] || bundler['path']
    bundler_path_option = bundler_path.nil? ? '' : "--path=#{bundler_path}"
    sh "bundle check #{bundler_path_option} || bundle install #{bundler_path_option} --jobs=4 --retry=3"
  end

  desc 'Update brew and install/update formulas'
  task :brew do
    brew = Config.instance['setup.brew']
    next if disabled? brew
    formulas = brew['formulas']
    next if formulas.nil?
    brew_update
    formulas.each { |formula| brew_install formula }
  end

  def brew_update
    sh 'brew update || brew update'
  end

  def brew_install(formula)
    raise 'no formula' if formula.to_s.strip.empty?
    sh " ( brew list #{formula} ) && ( brew outdated #{formula} || brew upgrade #{formula} ) || ( brew install #{formula} ) "
  end

  # - Dependencies

  task dependencies: %i[submodules cocoapods carthage]

  desc 'Updated submodules'
  task :submodules do
    submodules = Config.instance['setup.submodules']
    next if disabled? submodules
    sh 'git submodule update --init --recursive'
  end

  # -- CocoaPods

  desc 'CocoaPods'
  task :cocoapods do
    cocoapods = Config.instance['setup.cocoapods']
    next if disabled? cocoapods
    if needs_to_run_pod_install
      pod_repo_update
      pod_install
    else
      puts 'Skipping pod install because Pods seems updated'
    end
  end

  desc 'Pod repo update'
  task :pod_repo_update do
    pod_repo_update
  end

  desc 'Pod install'
  task :pod_install do
    pod_install
  end

  def needs_to_run_pod_install
    !FileUtils.identical?(Path.of('Podfile.lock'), Path.of('Pods/Manifest.lock'))
  rescue Exception => _
    true
  end

  def pod_repo_update
    sh 'bundle exec pod repo update --silent'
  end

  def pod_install
    sh 'bundle exec pod install'
  end

  # -- Carthage

  desc 'Carthage'
  task :carthage do
    carthage = Config.instance['setup.carthage']
    next if disabled? carthage
    Rake::Task['setup:carthage_install'].invoke
  end

  CARTHAGE_OPTIONS = '--platform iOS --no-use-binaries'

  task :carthage_install, [:dependency] do |_t, args|
    dependency = args[:dependency]
    sh "carthage bootstrap #{CARTHAGE_OPTIONS} #{dependency}"
  end

  desc 'Install carthage dependencies'
  task :carthage_update, [:dependency] do |_t, args|
    dependency = args[:dependency]
    sh "carthage update #{CARTHAGE_OPTIONS} #{dependency}"
  end

  task :carthage_clean, [:dependency] do |_t, args|
    has_dependency = !args[:dependency].to_s.strip.empty?
    sh 'rm -rf "~/Library/Caches/org.carthage.CarthageKit/"' unless has_dependency
    sh "rm -rf '#{Path.base}/Carthage/'" unless has_dependency
  end
end
