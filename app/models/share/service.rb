class Share::Service
  def authenticated_share(klass, params)
    response = {}
    entry = Entry.find(params[:entry_id])
    params["entry_url"] = entry.fully_qualified_url
    if klass.active?
      # child classes using this need to implement add
      status = add(params)
      if status == 200
        response[:message] = "Saved to #{klass.label}."
      elsif status == 401
        klass.remove_access!
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
  end

  def determine_content(params)
    entry = Entry.find(params[:entry_id])
    if params[:readability] == "on"
      url = entry.fully_qualified_url
      key = FeedbinUtils.page_cache_key(url)
      content_info = Rails.cache.fetch(key) do
        MercuryParser.parse(url)
      end
      content = content_info.content
    else
      content = entry.content
    end
    content
  end

  def self.determine_content(params)
    new().determine_content(params)
  end

  def render_popover_template(url)
    ApplicationController.render template: "supported_sharing_services/popover.js.erb", locals: {url: url}, layout: nil
  end

  def link_options(entry)
    {url: Rails.application.routes.url_helpers.share_supported_sharing_service_path(@klass, entry),
     label: @klass.label,
     html_options: @klass.html_options}
  end
end
