
# 简单的测试脚本，验证我们对 --exclude-pattern 的修改
$LOAD_PATH.unshift File.join(File.dirname(__FILE__), 'lib')
require 'rspec/core/option_parser'

# 测试单个 --exclude-pattern
puts "Test 1: Single --exclude-pattern"
options1 = RSpec::Core::Parser.parse(['--exclude-pattern', 'a/**/*_spec.rb'])
puts "Result: #{options1[:exclude_pattern]}"
puts "Success: #{options1[:exclude_pattern] == 'a/**/*_spec.rb'}"
puts

# 测试多个 --exclude-pattern
puts "Test 2: Multiple --exclude-pattern"
options2 = RSpec::Core::Parser.parse(['--exclude-pattern', 'a/**/*_spec.rb', '--exclude-pattern', 'b/**/*_spec.rb'])
puts "Result: #{options2[:exclude_pattern]}"
puts "Success: #{options2[:exclude_pattern] == 'a/**/*_spec.rb,b/**/*_spec.rb'}"
puts

# 测试与 --pattern 同时使用
puts "Test 3: --pattern and --exclude-pattern together"
options3 = RSpec::Core::Parser.parse(['--pattern', 'spec/**/*_spec.rb', '--exclude-pattern', 'a/**/*_spec.rb', '--exclude-pattern', 'b/**/*_spec.rb'])
puts "Pattern: #{options3[:pattern]}"
puts "Exclude pattern: #{options3[:exclude_pattern]}"
puts "Success: #{options3[:pattern] == 'spec/**/*_spec.rb' && options3[:exclude_pattern] == 'a/**/*_spec.rb,b/**/*_spec.rb'}"
