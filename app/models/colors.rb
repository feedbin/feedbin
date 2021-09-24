class Colors
  OPTIONS = ActiveSupport::HashWithIndifferentAccess.new({
    day: "#FFFFFF",
    sunset: "#f5f2eb",
    dusk: "#262626",
    midnight: "#000000"
  })

  def self.fetch(theme)
    new().fetch(theme)
  end

  def fetch(theme)
    OPTIONS.fetch(theme, OPTIONS[:day])
  end
end
