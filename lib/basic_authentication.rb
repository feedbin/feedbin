class BasicAuthentication
  def initialize(app)
    @app = app
  end

  def call(env)
    excluded_headers = ['Basic', 'ApplePushNotifications', 'Bearer']

    if env['HTTP_AUTHORIZATION'].respond_to?(:include?) && excluded_headers.none? { |header| env['HTTP_AUTHORIZATION'].include?(header) }
      env['HTTP_AUTHORIZATION'] = "Basic #{env['HTTP_AUTHORIZATION']}"
    end
    @app.call(env)
  end
end