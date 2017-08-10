ActiveSupport::Notifications.subscribe('process_action.action_controller') do |name, start, finish, id, payload|
  if payload[:params]['controller'] && payload[:params]['action']
    if finish && start
      time = (finish - start) * 1000
      Librato.timing "controller.#{payload[:params]['controller'].gsub('/', '_')}.#{payload[:params]['action']}.time", time
      if payload[:params].present? && payload[:params]['subdomain'].present? && payload[:params]['subdomain'] == 'api'
        Librato.timing "response_time.api", time, source: Socket.gethostname
      else
        Librato.timing "response_time.web", time, source: Socket.gethostname
      end
    end
    if payload[:db_runtime]
      Librato.timing "controller.#{payload[:params]['controller'].gsub('/', '_')}.#{payload[:params]['action']}.time.db", payload[:db_runtime]
    end
    if payload[:view_runtime]
      Librato.timing "controller.#{payload[:params]['controller'].gsub('/', '_')}.#{payload[:params]['action']}.time.view", payload[:view_runtime]
    end
  end
end

ActiveSupport::Notifications.subscribe("rack.queue-metrics.queue-depth") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  payload = event.payload
  Librato.measure "rack.queue-metrics.queue-depth.active", payload[:requests][:active], source: Socket.gethostname
  Librato.measure "rack.queue-metrics.queue-depth.queued", payload[:requests][:queued], source: Socket.gethostname
end