# frozen_string_literal: true

class WorkerStat
  def call(worker, item, queue)
    title = "worker.#{worker.class}"
    Librato.increment "#{title}.count"
    Librato.timing title, percentile: [95] do
      yield
    end
  end
end
