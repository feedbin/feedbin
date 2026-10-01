# Step 3: mailer methods with no caller. Their templates go with them.
# Run with: bin/rails runner $SWEEP/bin/mailers.rb
require_relative "lib"

Rails.application.eager_load!

rows = []
ActionMailer::Base.descendants.select(&:name).each do |klass|
  klass.action_methods.each do |action|
    method = klass.instance_method(action)
    next unless method.owner == klass
    file, line = method.source_location
    next unless file.start_with?(Rails.root.to_s)
    file = file.delete_prefix("#{Rails.root}/")
    # Previews live in test/, so a preview-only caller counts as a test caller.
    prod, test = refs(action, own_files: [file], boundary: "A-Za-z0-9_")
    templates = Dir.glob("app/views/#{klass.name.underscore}/#{action}.*")
    rows << classify("#{klass.name}##{action}", "#{file}:#{line}", prod, test, note: "templates: #{templates.join(" ")}")
  end
end

write_rows("mailers", rows)
