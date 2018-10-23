class TLDLength
  def initialize(app)
    @app = app
  end

  def call(env)
    if Rails.env.development? && env["HTTP_HOST"] && env["HTTP_HOST"].split(".").length == 4
      ActionDispatch::Http::URL.tld_length = 2
    end
    @app.call(env)
  end
end
