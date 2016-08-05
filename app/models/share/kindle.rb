class Share::Kindle < Share::Service
  def initialize(klass)
    @klass = klass
  end

  def share(params)
    response = {}
    if @klass.kindle_address.present?
      SendToKindle.perform_async(params[:entry_id], @klass.kindle_address)
      response[:message] = "Article sent to #{@klass.label}."
    else
      response[:message] = "Please provide a #{@klass.label} email address."
      response[:url] = Rails.application.routes.url_helpers.sharing_services_path
    end
    response
  end
end
