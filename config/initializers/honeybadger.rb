Honeybadger.configure do |config|
  config.api_key = ENV['HONEYBADGER_API_KEY']
  config.async do |notice|
    SendExceptions.perform_async(notice.to_json)
  end
end