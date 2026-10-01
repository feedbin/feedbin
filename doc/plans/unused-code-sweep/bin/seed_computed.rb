# Step 0: build out/computed.tsv from out/computed_auto.tsv.
# Drops prefixes that cannot name a unit, narrows broad prefixes to their real
# values, and adds names that vendored libraries and Rails build at runtime.
# Re-run computed_sites.rb first. Review the result by hand (plan, Task 1).
require_relative "lib"

auto = File.readlines(File.join(OUT, "computed_auto.tsv"), chomp: true).map { |l| l.split("\t") }

# Prefixes that are URLs, cache keys, data attributes, or CSS at-rules.
DROP = /\A(\/\/|\/|data-|media\z|pg-|id_|action_|pages_|newsletter_|web_sub_|url_cache_|image_|iframe_embed_|refresher_|root_meta_|audio_|youtube_embed_|subscription_checkbox_|expandable_|feedbin-client-|feedbin-server-|\.)/

# Broad prefixes replaced by the exact values their site can produce.
NARROW = {
  "icon-" => [%w[icon-round icon-square], "favicon_component.rb:53 icon-\#{format}; Image#icon_format returns round or square"]
}.freeze

EXTRA = [
  ["prefix", "hljs-", "vendor highlight.js builds hljs-\#{scope}"],
  ["prefix", "mejs__", "vendor MediaElement default classPrefix"],
  ["prefix", "mejs_empty__", "audio.js.coffee:28 classPrefix: 'mejs_empty__'"],
  ["prefix", "bs-tooltip-", "vendor Bootstrap tooltip builds bs-tooltip-\#{placement}"],
  ["prefix", "bigfoot-footnote", "vendor Bigfoot builds its class names"],
  ["name", "field_with_errors", "Rails ActionView::Base.field_error_proc"]
].freeze

rows = []
auto.each do |kind, value, site|
  next if value.match?(DROP)
  if (narrow = NARROW[value])
    narrow[0].each { |name| rows << ["name", name, narrow[1]] }
  else
    rows << [kind, value, site]
  end
end
rows.concat(EXTRA)

File.open(File.join(OUT, "computed.tsv"), "w") do |f|
  f.puts "# kind\tvalue\tsite (reviewed by hand; see the plan, Task 1)"
  rows.uniq { |r| r[1] }.each { |r| f.puts r.join("\t") }
end
File.write(File.join(OUT, "computed_reviewed.txt"), auto.map { |r| r[1] }.sort.uniq.join("\n") + "\n")
puts "#{rows.size} rows -> #{File.join(OUT, "computed.tsv")}"
