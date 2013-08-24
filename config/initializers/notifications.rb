ActiveSupport::Notifications.subscribe do |name, start, finish, id, payload|
  if 'process_action.action_controller' == name && payload[:params]['controller'] && payload[:params]['action']
    if finish && start
      Librato.timing "controller.#{payload[:params]['controller'].gsub('/', '_')}.#{payload[:params]['action']}.time", (finish - start) * 1000
    end
    if payload[:db_runtime]
      Librato.timing "controller.#{payload[:params]['controller'].gsub('/', '_')}.#{payload[:params]['action']}.time.db", payload[:db_runtime]
    end
    if payload[:view_runtime]
      Librato.timing "controller.#{payload[:params]['controller'].gsub('/', '_')}.#{payload[:params]['action']}.time.view", payload[:view_runtime]
    end
  end
end