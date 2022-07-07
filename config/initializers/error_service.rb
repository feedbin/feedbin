class ErrorService
  def self.notify(params)
    Honeybadger.notify(params)

    return unless Rails.env.development?

    exception = params

    unless exception.is_a?(Exception)
      Rails.logger.error params
      exception = params.respond_to?(:dig) && params.dig(:parameters, :exception)
    end

    return unless exception.respond_to?(:message) && exception.respond_to?(:backtrace)

    Rails.logger.error ([exception.message] + exception.backtrace).join($/)
  end

  def self.context(params)
    Honeybadger.context(params)
  end
end