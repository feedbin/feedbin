class Share::Service

  class AuthError < StandardError; end

  def authenticated_share(klass, params)
    response = {}
    entry = Entry.find(params[:entry_id])
    params["entry_url"] = entry.fully_qualified_url
    if klass.active?
      # child classes using this need to implement add
      status = add(params)
      if status == 200
        response[:message] = "Sent to #{klass.label}."
      elsif status == 401
        klass.auth_error!
        response[:url] = Rails.application.routes.url_helpers.sharing_services_path
        response[:error] = "#{klass.label} authentication error."
      else
        response[:error] = "There was a problem connecting to #{klass.label}."
        ShareRetry.perform_in(1.minute, klass.id, params)
      end
    else
      response[:url] = Rails.application.routes.url_helpers.sharing_services_path
      response[:error] = "#{klass.label} authentication error."
    end
    response
  rescue => exception
    raise unless Rails.env.production?
    ErrorService.notify(exception)
    response[:error] = "Unknown share error."
  end

  def determine_content(params)
    entry = Entry.find(params[:entry_id])
    if params[:readability] == "on"
      url = entry.fully_qualified_url
      content_info = MercuryParser.parse(url)
      content = content_info.content
    else
      content = entry.content
    end
    content
  end

  def self.determine_content(params)
    new.determine_content(params)
  end

  def render_popover_template(url)
    ApplicationController.render template: "supported_sharing_services/popover", formats: :js, locals: {url: url}, layout: nil
  end

  def share_link
    {
      url: Rails.application.routes.url_helpers.share_supported_sharing_service_path(@klass, 9_999_999_999),
      label: @klass.label,
      html_options: @klass.html_options
    }
  rescue
    nil
  end
end
