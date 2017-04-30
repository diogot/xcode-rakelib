# frozen_string_literal: true

desc 'Run SwiftGen'
task swiftgen: %i[swiftgen:strings]

namespace 'swiftgen' do
  desc 'Generate strings'
  task :strings do
    config = Config.instance.active'swiftgen.strings'
    next if config.nil?
    path = config['path']
    template = config['template']
    files = config['strings']
    files.each do |strings, generated|
      sh "#{path} strings -template #{template} --output '#{generated}' '#{strings}'"
    end
  end
end
