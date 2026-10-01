# Step 1: routes and controller actions.
# Run with: bin/rails runner $SWEEP/bin/routes.rb
require_relative "lib"

Rails.application.eager_load!

PUBLIC_PATH = %r{\A/(v1|v2|extension|app_store|public|podcasts|\.well-known|404|422|500)(/|\z)}
FRAMEWORK = %r{\A(rails|active_storage|action_mailbox|stripe_event)/}

routes = Rails.application.routes.routes.filter_map do |r|
  controller = r.defaults[:controller]
  next if controller.nil? || controller.match?(FRAMEWORK)
  {
    controller: controller,
    action: r.defaults[:action].to_s,
    name: r.name,
    verb: r.verb,
    path: r.path.spec.to_s.sub("(.:format)", ""),
    public: r.constraints[:subdomain] == "api" || r.path.spec.to_s.match?(PUBLIC_PATH) || controller.start_with?("api/")
  }
end
routed = routes.map { |r| [r[:controller], r[:action]] }.to_set

controllers = (ActionController::Base.descendants + ActionController::API.descendants).reject(&:abstract?)
controllers.select! { |k| k.name && k.instance_methods(false).any? { |m| k.instance_method(m).source_location&.first&.start_with?(Rails.root.to_s) } }
rows = []

# A. Public methods that no route reaches and no code calls.
#    (A public method with callers is a helper or callback target: out of scope.)
controllers.each do |klass|
  path = klass.controller_path
  klass.action_methods.each do |action|
    method = klass.instance_method(action)
    next unless method.owner == klass
    next if routed.include?([path, action])
    file, line = method.source_location
    next unless file.start_with?(Rails.root.to_s)
    file = file.sub("#{Rails.root}/", "")
    prod, test = refs(action.to_s.sub(/[?!=]\z/, ""), ignore_line: /\bdef\s+#{Regexp.escape(action)}/)
    rows << classify("#{path}##{action}", "#{file}:#{line}", prod, test, note: "public method with no route")
  end
end

# B. Routes whose action does not exist and has no template.
routes.each do |r|
  klass = "#{r[:controller]}_controller".camelize.safe_constantize
  next if klass&.action_methods&.include?(r[:action])
  next if Dir.glob("app/views/#{r[:controller]}/#{r[:action]}.*").any?
  rows << classify("#{r[:controller]}##{r[:action]}", "config/routes.rb #{r[:verb]} #{r[:path]}", [], [], decision: r[:public], note: "route with no action and no template")
end

# C. Route groups (all routes with one path). A group is used when its helper
#    or its literal path has a caller. Public groups go to the decision list.
routes.group_by { |r| r[:path] }.each do |path, group|
  name = group.map { |r| r[:name] }.compact.first
  prod, test = [], []
  if name
    %w[_path _url].each do |suffix|
      p_, t_ = refs("#{name}#{suffix}")
      prod += p_
      test += t_
    end
  end
  static = path.split("/:").first.to_s
  if static.length > 1
    p_, t_ = refs(static, boundary: "A-Za-z0-9_/-")
    prod += p_.reject { |l| l.start_with?("config/routes.rb:") }
    test += t_
  end
  actions = group.map { |r| "#{r[:verb]} #{r[:controller]}##{r[:action]}" }.join(", ")
  model = name && name.sub(/\A(new_|edit_)/, "").singularize.camelize.safe_constantize
  note = actions
  note += "; #{model} is a model: check polymorphic use (form_with model:, link_to record, redirect_to record, url_for)" if model.is_a?(Class) && model < ActiveRecord::Base
  rows << classify(name ? "#{name}_path" : path, "config/routes.rb #{path}", prod, test, decision: group.any? { |r| r[:public] }, note: note)
end

write_rows("routes", rows)
