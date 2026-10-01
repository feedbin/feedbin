# Step 6a: Stimulus controllers with no data-controller, and Stimulus methods
# with no data-action and no caller. Phlex's stimulus() helper takes snake_case
# symbols (controller: :search_token, actions: {"click" => :toggle_open}), so
# both the dashed/camelCase and the snake_case forms count.
# Usage: ruby $SWEEP/bin/stimulus.rb
require_relative "lib"

LIFECYCLE = /\A(constructor|initialize|connect|disconnect|\w+(TargetConnected|TargetDisconnected|ValueChanged|OutletConnected|OutletDisconnected))\z/
KEYWORDS = %w[if for while switch catch function return].to_set

rows = []
tracked("app/javascript/controllers").select { |f| f.end_with?("_controller.js") }.each do |file|
  id = file.delete_prefix("app/javascript/controllers/").delete_suffix("_controller.js").gsub("/", "--").tr("_", "-")
  snake = id.tr("-", "_")
  prod, test = refs(id, own_files: [file])
  p2, t2 = refs(snake, own_files: [file], boundary: "A-Za-z0-9_")
  rows << classify(id, file, prod + p2.grep(/controller|stimulus/), test + t2, note: "Stimulus controller")

  File.readlines(file).each_with_index do |line, i|
    m = line.match(/^  (?:async |get |set |static )?([a-zA-Z_]\w*)\s*\(/)
    next unless m
    name = m[1]
    next if name.match?(LIFECYCLE) || KEYWORDS.include?(name)
    def_line = /^\s*(async |get |set |static )?#{name}\s*\(/
    prod, test = refs(name, ignore_line: def_line, boundary: "A-Za-z0-9_")
    snake_name = name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
    if prod.empty? && snake_name != name
      prod, t2 = refs(snake_name, boundary: "A-Za-z0-9_")
      test += t2
    end
    rows << classify("#{id}##{name}", "#{file}:#{i + 1}", prod, test, note: "Stimulus method")
  end
end
write_rows("stimulus", rows)
