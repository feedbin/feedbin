class BasicAuthentication
  def initialize(app)
    @app = app
  end

  def call(env)
    if env["HTTP_AUTHORIZATION"].respond_to?(:include?) && !env["HTTP_AUTHORIZATION"].include?("Basic") && !env["HTTP_AUTHORIZATION"].include?("ApplePushNotifications")
      env["HTTP_AUTHORIZATION"] = "Basic #{env["HTTP_AUTHORIZATION"]}"
    end
    @app.call(env)
  end
end
