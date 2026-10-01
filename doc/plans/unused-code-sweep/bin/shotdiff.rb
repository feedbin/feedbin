# Click-through screenshot diff (spec 7.2). Uses ImageMagick through `magick`:
# a bare `compare` on this Mac runs Araxis Merge.
#
# Calibrate (step 0, two baseline walks with no code change):
#   ruby shotdiff.rb calibrate shots/baseline shots/baseline2
#   -> writes shots/thresholds.tsv (name, changed pixels between the two walks)
# Compare (after each category):
#   ruby shotdiff.rb compare shots/baseline shots/<label>
#   -> prints one line per screen; FLAG lines need a look. Diff images go to shots/<label>/diff/
require "open3"

mode, base_dir, run_dir = ARGV
abort "usage: shotdiff.rb calibrate|compare <baseline_dir> <run_dir>" unless %w[calibrate compare].include?(mode) && run_dir

def size(path) = Open3.capture2("magick", "identify", "-format", "%wx%h", path).first

def changed(a, b, diff_out)
  _, err, _ = Open3.capture3("magick", "compare", "-metric", "AE", "-fuzz", "2%", a, b, diff_out)
  err[/\A\s*([\d.e+]+)/, 1].to_f.round
end

thresholds_path = File.join(File.dirname(base_dir), "thresholds.tsv")
thresholds = File.exist?(thresholds_path) ? File.readlines(thresholds_path, chomp: true).to_h { |l|
  n, v = l.split("\t")
  [n, v.to_i]
} : {}
SLACK = 200 # pixels above the calibrated noise before a screen is flagged

results = Dir.glob(File.join(base_dir, "*.png")).sort.map do |a|
  name = File.basename(a, ".png")
  b = File.join(run_dir, "#{name}.png")
  next [name, "MISSING", nil] unless File.exist?(b)
  next [name, "SIZE #{size(a)} -> #{size(b)}", nil] if size(a) != size(b)
  Dir.mkdir(File.join(run_dir, "diff")) unless Dir.exist?(File.join(run_dir, "diff"))
  [name, nil, changed(a, b, File.join(run_dir, "diff", "#{name}.png"))]
end

if mode == "calibrate"
  File.write(thresholds_path, results.map { |n, _, px| "#{n}\t#{px.to_i}" }.join("\n") + "\n")
  puts "thresholds -> #{thresholds_path}"
  results.each { |n, problem, px| puts [n, problem || px].join("\t") }
else
  results.each do |name, problem, px|
    limit = thresholds.fetch(name, 0) + SLACK
    status = if problem
      "FLAG #{problem}"
    else
      ((px > limit) ? "FLAG #{px}px > #{limit}px" : "ok #{px}px")
    end
    puts "#{status}\t#{name}"
  end
end
