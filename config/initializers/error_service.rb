class ErrorService
  def self.notify(exception, options = {})
    if exception.is_a?(Exception)
      Honeybadger.notify(exception, options)
    else
      Honeybadger.notify(exception)
      Rails.logger.error exception
      exception = exception.respond_to?(:safe_dig) && exception.safe_dig(:parameters, :exception)
    end

    return unless exception.respond_to?(:message) && exception.respond_to?(:backtrace)

    Rails.logger.error ([exception.message] + exception.backtrace).join($/)
  end

  def self.context(params)
    Honeybadger.context(params)
  end
end