class Share::Facebook < Share::Service
  URL = "https://www.facebook.com/sharer/sharer.php"

  def initialize(klass = nil)
    @klass = klass
  end

  def share(params, entry = nil)
    if entry.blank?
      entry = Entry.find(params[:entry_id])
    end
    uri = URI.parse(URL)
    uri.query = {"u" => entry.fully_qualified_url, "display" => "popup"}.to_query
    {text: "feedbin.sharePopup('#{uri}'); return false;"}
  end

  def link_options(entry)
    action = share(nil, entry)
    defaults = super
    defaults.merge({
      html_options: {onclick: action[:text]},
    })
  end
end
