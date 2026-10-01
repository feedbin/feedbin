# Step 2: ERB/jbuilder/builder templates and Phlex views/components.
# Run with: bin/rails runner $SWEEP/bin/views.rb
require_relative "lib"

Rails.application.eager_load!

routed = Rails.application.routes.routes.filter_map { |r| [r.defaults[:controller], r.defaults[:action].to_s] if r.defaults[:controller] }.to_set
controllers = (ActionController::Base.descendants + ActionController::API.descendants).select(&:name)
mailers = ActionMailer::Base.descendants.select(&:name).to_h { |k| [k.name.underscore, k] }

rows = []
TEMPLATE = /\.(html|text|js|json|xml|css)?\.?(erb|jbuilder|builder)\z/

tracked("app/views").each do |file|
  next if file.end_with?(".rb") || File.basename(file).start_with?(".")
  next unless file.match?(TEMPLATE)
  rel = file.delete_prefix("app/views/")
  dir = File.dirname(rel)
  base = File.basename(rel).split(".").first

  if base.start_with?("_")
    # Partial: "dir/name" anywhere, or "name" from the same directory or its controller.
    name = base.delete_prefix("_")
    logical = "#{dir}/#{name}"
    prod, test = refs(logical, own_files: [file], boundary: "A-Za-z0-9_/")
    if prod.empty?
      local = (tracked("app/views/#{dir}") + tracked("app/controllers/#{dir}_controller.rb")) - [file]
      prod = local.empty? ? [] : grep_name(name, local, boundary: "A-Za-z0-9_")
    end
    if prod.empty? && (model = name.camelize.safe_constantize).is_a?(Class) && model < ActiveRecord::Base
      # render @records / render record picks "<plural>/_<singular>" by itself.
      out, _ = Open3.capture2("git", "grep", "-n", "-E", "-e", "render[ (]+(partial: *)?@?[a-z_.]*\\b(#{name}|#{name.pluralize})\\b", "--", "app")
      prod = out.lines.map(&:chomp)
    end
    rows << classify(logical, file, prod, test, note: "partial")
  elsif dir == "layouts"
    prod, test = refs(base, own_files: [file])
    prod += ["implicit: controller or mailer named #{base}"] if controllers.any? { |k| k.controller_path == base } || mailers.key?(base)
    rows << classify("layouts/#{base}", file, prod, test, note: "layout")
  else
    # Action template: reached by its action, a route (implicit action), or an explicit render.
    prod, test = refs("#{dir}/#{base}", own_files: [file], boundary: "A-Za-z0-9_/")
    prod += ["routed action #{dir}##{base}"] if routed.include?([dir, base])
    prod += ["mailer #{dir}##{base}"] if mailers[dir]&.action_methods&.include?(base)
    if prod.empty? && File.exist?("app/controllers/#{dir}_controller.rb")
      prod = grep_name(base, ["app/controllers/#{dir}_controller.rb"], boundary: "A-Za-z0-9_")
    end
    rows << classify("#{dir}/#{base}", file, prod, test, note: "action or mailer template")
  end
end

# Phlex views and components: the class name, or the snake_case name for
# ApplicationHelper#component(:name), or a Phlex::Kit call Name(...).
tracked("app/views").select { |f| f.end_with?(".rb") }.each do |file|
  klass = File.read(file)[/^\s*class\s+([A-Z]\w*)/, 1]
  next unless klass
  prod, test = refs(klass, own_files: [file], boundary: "A-Za-z0-9_")
  if prod.empty? && klass.end_with?("Component")
    p_, t_ = refs(klass.delete_suffix("Component").underscore, own_files: [file], boundary: "A-Za-z0-9_")
    prod += p_.grep(/component[ (]+:/)
    test += t_
  end
  rows << classify(klass, file, prod, test, note: "Phlex class")
end

write_rows("views", rows)
