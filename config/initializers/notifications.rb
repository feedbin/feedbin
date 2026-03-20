ActiveSupport::Notifications.subscribe("process_action.action_controller") do |name, start, finish, id, payload|
  if payload[:params]["controller"] && payload[:params]["action"]
    controller = payload[:params]["controller"].tr("/", "_")
    action = payload[:params]["action"]
    if finish && start
      time = (finish - start) * 1000
      Librato.timing "controller.#{controller}.#{action}.time", time, source: "total"
      if payload[:params].present? && payload[:params]["subdomain"].present? && payload[:params]["subdomain"] == "api"
        Librato.timing "response_time.api", time, source: Socket.gethostname
      else
        Librato.timing "response_time.web", time, source: Socket.gethostname
      end
    end
    if payload[:db_runtime]
      Librato.timing "controller.#{controller}.#{action}.time", payload[:db_runtime], source: "db"
    end
    if payload[:view_runtime]
      Librato.timing "controller.#{controller}.#{action}.time", payload[:view_runtime], source: "view"
    end
  end
end
