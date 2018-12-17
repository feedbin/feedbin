class Share::AppDotNet < Share::Service
  URL = "https://account.app.net/intent/post"

  def initialize(klass = nil)
    @klass = klass
  end

  def share(params, entry = nil)
    if entry.blank?
      entry = Entry.find(params[:entry_id])
    end
    uri = URI.parse(URL)
    uri.query = {"url" => entry.fully_qualified_url, "text" => entry.title}.to_query
    {text: "feedbin.sharePopup('#{uri.to_s}'); return false;"}
  end

  def link_options(entry)
    action = share(nil, entry)
    defaults = super
    defaults.merge({
      html_options: {onclick: action[:text]},
    })
  end
end
