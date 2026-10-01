# Step 7: CSS classes in the compiled application.css (from application.scss,
# theme.scss, functions.scss) that no view, Ruby file, or script uses.
# Tailwind output (app/assets/builds) is not checked: Tailwind already drops
# unused classes. Run with: bin/rails runner $SWEEP/bin/styles.rb
require_relative "lib"

css = Rails.application.assets.find_asset("application.css").to_s.gsub(%r{/\*.*?\*/}m, "")

# Selector text is everything before a "{" that is not an at-rule prelude.
selectors = Hash.new { |h, k| h[k] = [] }
css.scan(/([^{}]+)\{/) do |(sel)|
  sel = sel.strip
  next if sel.start_with?("@") || sel.match?(/\A(from|to|\d+%)/)
  sel.split(",").each do |one|
    one.scan(/\.(-?[_a-zA-Z][_a-zA-Z0-9-]*)/) { |(c)| selectors[c] << one.strip }
  end
end

# One token set per side is much faster than one git grep per class.
tokens = lambda do |paths|
  files = Open3.capture2("git", "ls-files", "--", *paths, *EXCLUDES, ":(exclude)app/assets/stylesheets", ":(exclude)vendor/assets").first.lines.map(&:chomp)
  files.each_with_object(Set.new) { |f, set| File.read(f).scrub.scan(/[A-Za-z0-9_-]+/) { |t| set << t } if File.file?(f) }
end
prod_tokens = tokens.call(PROD_PATHS)
test_tokens = tokens.call(TEST_PATHS)
vendor_tokens = Open3.capture2("git", "ls-files", "--", "vendor/assets/javascripts", "app/assets/javascripts/lib").first.lines.map(&:chomp)
  .each_with_object(Set.new) { |f, set| File.read(f).scrub.scan(/[A-Za-z0-9_-]+/) { |t| set << t } }

rows = selectors.map do |klass, sels|
  prod = prod_tokens.include?(klass) ? ["token"] : []
  test = test_tokens.include?(klass) ? ["token"] : []
  where = `git grep -n -F -e ".#{klass}" -- app/assets/stylesheets`.lines.first.to_s.split(":").first(2).join(":")
  if where.empty?
    Row.new("kept", klass, "vendor/assets/stylesheets", prod, test, "defined only in a vendored stylesheet")
  elsif prod.empty? && vendor_tokens.include?(klass)
    Row.new("kept", klass, where, prod, test, "a vendored library emits it")
  elsif prod.empty? && sels.all? { |s| s.include?(".content-styles") || s.include?(".entry-content") }
    Row.new("kept", klass, where, prod, test, "content scope (spec 5.1 item 5): third-party HTML can carry it; #{sels.first}")
  else
    classify(klass, where, prod, test, note: sels.first(2).join(" | "))
  end
end
write_rows("styles", rows)
