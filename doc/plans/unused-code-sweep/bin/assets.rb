# Step 8: SVG icons, images, and fonts with no reference.
# The unit is the path under its asset folder without the extension
# (for example suggested-categories/category-1), so computed prefixes match.
# The search uses the file name only.
# Usage: ruby $SWEEP/bin/assets.rb
require_relative "lib"

files = tracked("app/assets/svg") + tracked("app/assets/images") + tracked("app/assets/fonts")
files.reject! { |f| File.basename(f).start_with?(".") }

rows = files.map do |file|
  unit = file.sub(%r{\Aapp/assets/(svg|images|fonts)/}, "").sub(/\.[^.\/]+\z/, "")
  prod, test = refs(File.basename(unit))
  classify(unit, file, prod, test)
end
write_rows("assets", rows)
