a = "spec/unit"
b = "spec/unit"
original = ["--default-path", a, b]
files_or_dirs = [b]

result = []
remaining_files = files_or_dirs.dup

original.each do |arg|
  index = remaining_files.index { |f| f.equal?(arg) }
  if index
    remaining_files.delete_at(index)
  else
    result << arg
  end
end

p result
