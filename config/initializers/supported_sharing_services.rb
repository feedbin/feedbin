services = []

services << {
  service_id: 'pocket',
  label: 'Pocket',
  requires_auth: true,
  service_type: 'oauth'
}

# services << {
#   service_id: 'readability',
#   label: 'Readability',
#   requires_auth: true,
#   service_type: 'xauth'
# }
#
# services << {
#   service_id: 'instapaper',
#   label: 'Instapaper',
#   requires_auth: true,
#   service_type: 'xauth'
# }
#
# services << {
#   service_id: 'email',
#   label: 'Email',
#   requires_auth: false,
#   service_type: 'email'
# }


Feedbin::Application.config.supported_services = services