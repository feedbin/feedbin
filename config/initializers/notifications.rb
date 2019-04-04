ActiveSupport::Notifications.subscribe("process_action.action_controller") do |name, start, finish, id, payload|
  if payload[:params]["controller"] && payload[:params]["action"]
    controller = payload[:params]["controller"].tr("/", "_")
    action = payload[:params]["action"]
    if finish && start
      time = (finish - start) * 1000
      Librato.timing "controller.#{controller}.#{action}.time", time, percentile: [95, 99]
      if payload[:params].present? && payload[:params]["subdomain"].present? && payload[:params]["subdomain"] == "api"
        Librato.timing "response_time.api", time, source: Socket.gethostname, percentile: [95, 99]
      else
        Librato.timing "response_time.web", time, source: Socket.gethostname, percentile: [95, 99]
      end
    end
    if payload[:db_runtime]
      Librato.timing "controller.#{controller}.#{action}.time.db", payload[:db_runtime], percentile: [95, 99]
    end
    if payload[:view_runtime]
      Librato.timing "controller.#{controller}.#{action}.time.view", payload[:view_runtime], percentile: [95, 99]
    end
  end
end
