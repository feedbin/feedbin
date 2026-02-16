class YjitStats
  def initialize(app)
    @app = app
  end

  def call(env)
    @app.call(env)
  ensure
    if RubyVM::YJIT.enabled? && Random.rand(100) == 0
      RubyVM::YJIT.runtime_stats.each do |name, value|
        Honeybadger.gauge "yjit.web.#{name}", -> { value }, source: Socket.gethostname
      end
    end
  end
end