class TLDLength
  def initialize(app)
    @app = app
  end

  def call(env)
    if Rails.env.development? && host = env["HTTP_HOST"]
      parts = host.split(".")
      if parts[0] == "api"
        ActionDispatch::Http::URL.tld_length = parts.length - 2
      end
    end
    @app.call(env)
  end
end
