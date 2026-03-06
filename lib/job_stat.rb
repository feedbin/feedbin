class JobStat
  def call(job, item, queue)
    title = "job.#{job.class.to_s.underscore.parameterize}"
    Appsignal.increment_counter "#{title}.count", 1
    Appsignal.increment_counter "job.count", 1
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
  ensure
    duration = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
    Appsignal.add_distribution_value title, duration, hostname: Socket.gethostname
  end
end
