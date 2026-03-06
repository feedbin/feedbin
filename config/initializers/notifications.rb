ActiveSupport::Notifications.subscribe("process_action.action_controller") do |name, start, finish, id, payload|
  if payload[:params]["controller"] && payload[:params]["action"]
    controller = payload[:params]["controller"].tr("/", "_")
    action = payload[:params]["action"]
    if finish && start
      time = (finish - start) * 1000
      Appsignal.add_distribution_value "controller.#{controller}.#{action}.time", time
      if payload[:params].present? && payload[:params]["subdomain"].present? && payload[:params]["subdomain"] == "api"
        Appsignal.add_distribution_value "response_time.api", time, hostname: Socket.gethostname
      else
        Appsignal.add_distribution_value "response_time.web", time, hostname: Socket.gethostname
      end
    end
    if payload[:db_runtime]
      Appsignal.add_distribution_value "controller.#{controller}.#{action}.time.db", payload[:db_runtime]
    end
    if payload[:view_runtime]
      Appsignal.add_distribution_value "controller.#{controller}.#{action}.time.view", payload[:view_runtime], hostname: Socket.gethostname
    end
  end
end
