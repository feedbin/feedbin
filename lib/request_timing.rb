class RequestTiming
  def initialize(app)
    @app = app
  end

  def call(env)
    start = (env["HTTP_X_REQUEST_START"] && env["HTTP_X_REQUEST_START"].respond_to?(:to_i)) ? env["HTTP_X_REQUEST_START"].to_i : Time.now.to_i
    received = Time.now.to_i
    @app.call(env.merge!({
      "request_timing.start" => start,
      "request_timing.received" => received,
      "request_timing.queued" => received - start
    }))
  end

end