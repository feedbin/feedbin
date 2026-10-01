# Step 5: custom config keys that an initializer sets and nothing reads.
# Usage: ruby $SWEEP/bin/config_keys.rb
require_relative "lib"

rows = []
out, _ = Open3.capture2("git", "grep", "-n", "-E", "-e", "(Feedbin::Application|Rails\\.application)\\.config\\.[a-z_]+ *=[^=]", "--", "config", "lib")
out.lines.each do |line|
  file, lineno, text = line.chomp.split(":", 3)
  key = text[/\.config\.([a-z_]+) *=/, 1]
  prod, test = refs("config.#{key}", ignore_line: /config\.#{key} *=[^=]/, boundary: "A-Za-z0-9_")
  rows << classify("config.#{key}", "#{file}:#{lineno}", prod, test, note: "custom config key")
end
write_rows("config_keys", rows.uniq(&:unit))
