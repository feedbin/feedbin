class JobStat
  def call(job, item, queue)
    title = "job.#{job.class.to_s.underscore.parameterize}"
    Librato.increment "#{title}.count"
    Librato.increment "job.count"
    Librato.timing title do
      yield
    end
  end
end
