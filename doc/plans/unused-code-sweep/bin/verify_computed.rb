# Guard for computed names (plan, Review Focus item 2). Every name that a
# computed site can produce must still resolve to a file. Run after Tasks 4 and 10,
# and in the final pass. Exit status 1 lists each missing file.
# The first run writes out/verify_computed.baseline.txt; later runs fail only
# on files missing now that were present at the baseline.
# Run with: bin/rails runner $SWEEP/bin/verify_computed.rb
require_relative "lib"

Rails.application.eager_load!

missing = []
need = ->(path, why) { missing << "#{path}  (#{why})" if Dir.glob(path).empty? }

SupportedSharingService::SERVICES.each do |s|
  id = s[:service_id]
  need.call("app/assets/svg/icon-share-#{id}.svg", "sharing_services/_icon.html.erb icon-share-\#{service_id}") if File.exist?("app/views/supported_sharing_services/_service_#{id}.html.erb")
  need.call("app/views/supported_sharing_services/_service_#{id}.html.erb", "_supported_sharing_service.html.erb service_\#{service_id}")
end

(0..9).each { |n| need.call("app/assets/svg/icon-number-#{n}.svg", "shared/_tweet.html.erb icon-number-\#{number}") }

IframeEmbed.descendants.each do |klass|
  name = klass.name.demodulize.downcase
  next if name == "default"
  need.call("app/assets/svg/icon-embed-source-#{name}.svg", "embeds/iframe_view.rb icon-embed-source-\#{clean_name}")
end

baseline_path = File.join(OUT, "verify_computed.baseline.txt")
unless File.exist?(baseline_path)
  File.write(baseline_path, missing.join("\n") + "\n")
  puts "verify_computed: baseline written (#{missing.size} already missing)"
  missing.each { |m| puts "  already missing: #{m}" }
  exit 0
end
new_missing = missing - File.readlines(baseline_path, chomp: true)
if new_missing.empty?
  puts "verify_computed: ok (#{missing.size} missing at baseline, none new)"
else
  puts "verify_computed: NEW MISSING FILES"
  new_missing.each { |m| puts "  #{m}" }
  exit 1
end
