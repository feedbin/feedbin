Autotuner.enabled = true

Autotuner.reporter = proc do |report|
  Rails.logger.info("autotuner--------------------------")
  Rails.logger.info(report.to_s)
  Rails.logger.info("autotuner--------------------------")
end

Autotuner.metrics_reporter = proc do |metrics|
  metrics.each do |key, value|
    Librato.measure "autotuner.#{key}", value
  end
end