require 'optparse'
args = ["spec/unit", "--default-path", "spec/unit"]
parser = OptionParser.new do |opts|
  opts.on('--default-path PATH') { |path| }
end
parser.parse!(args)
p args
