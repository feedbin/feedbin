# Step 6b: CoffeeScript functions with no caller, and data-behavior handlers
# whose behavior value no view, helper, or script emits.
# Functions in feedbin.init and feedbin.preInit (4-space keys) run on page load,
# so they are entry points; only their selectors are checked (part B).
# Usage: ruby $SWEEP/bin/coffee.rb
require_relative "lib"

files = tracked("app/assets/javascripts").select { |f| f.end_with?(".coffee", ".coffee.erb") }
rows = []

# A. Functions: 2-space keys in $.extend feedbin / class bodies, and feedbin.name = ->
files.each do |file|
  File.readlines(file).each_with_index do |line, i|
    m = line.match(/^  ([a-zA-Z_]\w*): *(\([^)]*\))? *[-=]>/) || line.match(/^feedbin\.([a-zA-Z_]\w*) *= *(\([^)]*\))? *[-=]>/)
    next unless m
    name = m[1]
    next if %w[constructor preInit init].include?(name)
    prod, test = refs(name, ignore_line: /^(  #{name}:|feedbin\.#{name} *=)/, boundary: "A-Za-z0-9_")
    rows << classify("feedbin.#{name}", "#{file}:#{i + 1}", prod, test, note: "CoffeeScript function")
  end
end

# B. data-behavior selectors with no emitter.
selectors = Hash.new { |h, k| h[k] = [] }
files.each do |file|
  File.readlines(file).each_with_index do |line, i|
    line.scan(/data-behavior~=['"]?([\w-]+)/) { |(v)| selectors[v] << "#{file}:#{i + 1}" }
  end
end
selectors.each do |value, where|
  prod, test = refs(value, ignore_line: /data-behavior~=['"]?#{Regexp.escape(value)}\b/, boundary: "A-Za-z0-9_")
  rows << classify("data-behavior=#{value}", where.first, prod, test, note: "selector at #{where.join(" ")}")
end

write_rows("coffee", rows)
