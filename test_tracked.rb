require 'optparse'

original_cli_args = ["--default-path", "spec/unit", "spec/unit", "--seed", "1234", "spec/unit"]

tracked_args = original_cli_args.map(&:dup)

# simulate Parser.parse
args = tracked_args.dup
options = {}
OptionParser.new do |opts|
  opts.on('--default-path PATH') { |p| options[:default_path] = p }
  opts.on('--seed SEED') { |s| options[:seed] = s }
end.parse!(args)

leftover_ids = args.map(&:object_id)

result = original_cli_args.reject.with_index do |_, i|
  leftover_ids.include?(tracked_args[i].object_id)
end

p result
