Rails.application.reloader.to_prepare do
  Feedbin::Application.config.font_sizes = (1..10).to_a
  Feedbin::Application.config.fonts = [
    Font.new("System", "default"),
    Font.new("System Serif", "serif-3"),
    Font.new("Whitney", "sans-serif-1"),
    Font.new("Sentinel", "serif-1"),
    Font.new("Ideal Sans", "sans-serif-2"),
    Font.new("Mercury", "serif-2"),
  ]
end
