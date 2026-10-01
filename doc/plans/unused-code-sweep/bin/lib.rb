# Shared helpers for the unused-code sweep. Plain Ruby, no Rails.
# Run every script from the repo root: ~/Sites/feedbin
require "open3"

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

SWEEP = File.expand_path("..", __dir__)
OUT = File.join(SWEEP, "out")
Dir.mkdir(OUT) unless Dir.exist?(OUT)

# Where a caller can live. test/ is searched separately (TEST_PATHS).
PROD_PATHS = %w[app lib config db/seeds.rb script bin public vendor/javascript config.ru Rakefile Procfile Gemfile].freeze
TEST_PATHS = %w[test].freeze

# Generated, vendored, or binary-ish files that would give false "used" hits.
EXCLUDES = %w[
  :(exclude)app/assets/javascripts/lib
  :(exclude)app/assets/builds
  :(exclude)app/assets/svg
  :(exclude)app/assets/images
  :(exclude)app/assets/fonts
  :(exclude)public/assets
  :(exclude)*.min.js
].freeze

# Characters that can be part of a name in Ruby, CSS classes, and file names.
NAME_CHARS = "A-Za-z0-9_-"

# git grep for a literal name with custom boundaries, so "foo" does not match
# "foo-bar" or "foo_bar". Returns ["path:line:text", ...].
def grep_name(name, paths, boundary: NAME_CHARS, extra_excludes: [])
  escaped = Regexp.escape(name).gsub("\\-", "-")
  pattern = "(^|[^#{boundary}])#{escaped}($|[^#{boundary}])"
  cmd = ["git", "grep", "-n", "-I", "-E", "-e", pattern, "--", *paths, *EXCLUDES, *extra_excludes]
  out, _status = Open3.capture2(*cmd)
  out.scrub.lines.map(&:chomp).map { |l| l[0, 220] }
end

# Callers of a name, split into production and test callers.
#   own_files:    files where the unit lives (their lines do not count)
#   ignore_line:  a regexp; matching lines do not count (for example the definition)
def refs(name, own_files: [], ignore_line: nil, boundary: NAME_CHARS)
  keep = lambda do |line|
    file = line.split(":", 2).first
    next false if own_files.include?(file)
    next false if ignore_line && line.split(":", 3)[2].to_s.match?(ignore_line)
    true
  end
  prod = grep_name(name, PROD_PATHS, boundary: boundary).select(&keep)
  test = grep_name(name, TEST_PATHS, boundary: boundary).select(&keep)
  [prod, test]
end

# out/computed.tsv lists names the code builds at runtime (spec 5.1 item 3).
# Columns: kind (name|prefix), value, site. Lines starting with # are comments.
def computed
  path = File.join(OUT, "computed.tsv")
  rows = File.exist?(path) ? File.readlines(path, chomp: true) : []
  rows = rows.reject { |l| l.strip.empty? || l.start_with?("#") }.map { |l| l.split("\t") }
  {
    names: rows.select { |r| r[0] == "name" }.to_h { |r| [r[1], r[2]] },
    prefixes: rows.select { |r| r[0] == "prefix" }.to_h { |r| [r[1], r[2]] }
  }
end

def computed_reason(name)
  c = computed
  return "computed name: #{c[:names][name]}" if c[:names].key?(name)
  hit = c[:prefixes].keys.find { |p| name.start_with?(p) }
  hit && "computed prefix #{hit}: #{c[:prefixes][hit]}"
end

# One row per unit. status is candidate, kept, or decision.
Row = Struct.new(:status, :unit, :defined_at, :prod_refs, :test_refs, :note)

def write_rows(category, rows)
  path = File.join(OUT, "#{category}.tsv")
  File.open(path, "w") do |f|
    f.puts %w[status unit defined_at prod_refs test_refs note].join("\t")
    rows.reject { |r| r.status == "used" }.sort_by { |r| [r.status, r.defined_at.to_s] }.each do |r|
      f.puts [r.status, r.unit, r.defined_at, r.prod_refs.size, r.test_refs.size, r.note].join("\t")
    end
  end
  counts = rows.group_by(&:status).transform_values(&:size)
  puts "#{category}: #{counts.inspect} -> #{path}"
  rows
end

# Classify one unit by its references.
def classify(unit, defined_at, prod, test, decision: false, note: nil)
  reason = computed_reason(unit)
  status =
    if reason then "kept"
    elsif !prod.empty? then "used"
    elsif decision then "decision"
    else "candidate"
    end
  Row.new(status, unit, defined_at, prod, test, [reason, note].compact.join("; "))
end

def tracked(glob)
  out, _ = Open3.capture2("git", "ls-files", "--", glob)
  out.lines.map(&:chomp)
end
