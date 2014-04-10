Feedbin::Application.config.supported_services = [
  SupportedSharingService.new(
    service_id: 'pocket',
    label: 'Pocket',
    requires_auth: true,
    type: 'oauth'
  ),
  SupportedSharingService.new(
    service_id: 'readability',
    label: 'Readability',
    requires_auth: true,
    type: 'xauth'
  )
]
