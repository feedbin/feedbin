# Step 0: list every place that builds a name at runtime.
# Writes out/computed_auto.tsv: one row per prefix, with every site that uses it.
# A person then reviews it and writes out/computed.tsv (see the plan, Task 1).
require_relative "lib"

PATTERNS = {
  # Ruby/ERB/CoffeeScript interpolation: "icon-share-#{x}"
  interpolation: /([A-Za-z0-9_\/.-]*[A-Za-z0-9_\/-])#\{/,
  # JavaScript template literal: `icon-${x}`
  template_literal: /([A-Za-z0-9_\/.-]*[A-Za-z0-9_\/-])\$\{/,
  # String concatenation: "icon-" + x  or  'icon-' + x
  concat: /["']([A-Za-z0-9_\/.-]*[-_\/])["']\s*\+/
}.freeze

out, _ = Open3.capture2("git", "grep", "-n", "-I", "-E", "-e", '#\{|\$\{|["\x27][A-Za-z0-9_/.-]*[-_/]["\x27] *\+',
  "--", "app", "lib", "config", *EXCLUDES, ":(exclude)app/assets/stylesheets")
sites = Hash.new { |h, k| h[k] = [] }
out.scrub.each_line do |line|
  file, lineno, text = line.chomp.split(":", 3)
  next unless text
  PATTERNS.each_value do |re|
    text.scan(re) { |(prefix)| sites[prefix] << "#{file}:#{lineno}" if prefix.length >= 3 }
  end
end

path = File.join(OUT, "computed_auto.tsv")
File.open(path, "w") do |f|
  sites.sort.each { |prefix, where| f.puts ["prefix", prefix, where.uniq.first(5).join(" ")].join("\t") }
end
puts "#{sites.size} prefixes -> #{path}"
