# frozen_string_literal: true

desc 'Generate strings'
task :swiftgen_strings do
  config = Config.instance['swiftgen']
  next if disabled? config
  path = config['path']
  config['strings'].each do |strings, generated|
    sh "#{path} strings -template dot-syntax-swift3 --output '#{generated}' '#{strings}'"
  end
end
