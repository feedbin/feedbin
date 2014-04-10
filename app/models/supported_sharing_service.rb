class SupportedSharingService

  attr_accessor :service_id, :label, :requires_auth, :type

  def initialize(params)
    params.each do |key, value|
      instance_variable_set("@#{key}", value) unless value.nil?
    end
  end

  def self.find(service_id)
    result = where(service_id: service_id).first
    raise ActiveRecord::RecordNotFound if result.nil?
    result
  end

  def self.where(params)
    results = []
    Feedbin::Application.config.supported_services.each do |supported_service|
      include_service = true
      params.each do |param, value|
        if supported_service.send(param) != value
          include_service = false
        end
      end
      results << supported_service if include_service
    end
    results
  end

  def requires_auth?
    self.requires_auth
  end

end
