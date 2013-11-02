Feedbin::Application.config.action_names = []
Feedbin::Application.config.action_names << ActionName.new(label: 'Mark as Read', value: 'mark_read')
Feedbin::Application.config.action_names << ActionName.new(label: 'Star', value: 'star')
Feedbin::Application.config.action_names << ActionName.new(label: 'Send Push Notification', value: 'send_push_notification')