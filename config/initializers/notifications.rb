ActiveSupport::Notifications.subscribe("process_action.action_controller") do |name, start, finish, id, payload|
  if payload[:params]["controller"] && payload[:params]["action"]
    controller = payload[:params]["controller"].tr("/", "_")
    action = payload[:params]["action"]
    if finish && start
      time = (finish - start) * 1000
      Honeybadger.histogram "controller.#{controller}.#{action}.time", duration: time
      if payload[:params].present? && payload[:params]["subdomain"].present? && payload[:params]["subdomain"] == "api"
        Honeybadger.histogram "response_time.api", duration: time, source: Socket.gethostname
      else
        Honeybadger.histogram "response_time.web", duration: time, source: Socket.gethostname
      end
    end
    if payload[:db_runtime]
      Honeybadger.histogram "controller.#{controller}.#{action}.time.db", duration: payload[:db_runtime]
    end
    if payload[:view_runtime]
      Honeybadger.histogram "controller.#{controller}.#{action}.time.view", duration: payload[:view_runtime], source: Socket.gethostname
    end
  end
end
