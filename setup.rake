# frozen_string_literal: true

# -- project setup

desc 'Install/update and configure project'
task setup: %i[setup:dependencies setup:configure]

namespace 'setup' do
  task dependencies: %i[install_dependencies] do
    bundler_path = ENV['BUNDLER_PATH'] || CONFIG['bundler']['path']
    if bundler_path.nil?
      sh 'bundle install'
    else
      sh "bundle check --path=#{bundler_path} || bundle install --path=#{bundler_path} --jobs=4 --retry=3"
    end
  end

  task configure: %i[pod_if_needed clean_artifacts]

  task :install_dependencies do
    # brew_update
    # brew_install 'carthage'
  end

  desc 'Updated submodules'
  task :submodule_update do
    # sh 'git submodule update --init --recursive'
  end

  # -- CocoaPods

  desc 'Run CocoaPods if needed'
  task :pod_if_needed do
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

  # -- brew

  def brew_update
    sh 'brew update || brew update'
  end

  def brew_install(formula)
    raise 'no formula' if formula.to_s.strip.empty?
    sh " ( brew list #{formula} ) && ( brew outdated #{formula} || brew upgrade #{formula} ) || ( brew install #{formula} ) "
  end
end
