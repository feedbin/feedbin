class Timer
  def initialize(timeout = 0)
    start
    @deadline = now + timeout.to_f
  end

  def expired?
    now > @deadline
  end

  def now
    ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
  end

  def elapsed
    (now - start).ceil(2)
  end

  def start
    @start ||= now
  end
end
