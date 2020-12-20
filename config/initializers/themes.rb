Rails.application.reloader.to_prepare do
  Feedbin::Application.config.themes = [
    Theme.new("Day", "day"),
    Theme.new("Sunset", "sunset"),
    Theme.new("Dusk", "dusk"),
    Theme.new("Night", "midnight"),
    Theme.new("Auto", "auto")
  ]
end
