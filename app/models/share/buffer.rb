class Share::Buffer < Share::Service
  URL = "http://bufferapp.com/add"

  def initialize(klass = nil)
    @klass = klass
  end

  def share(params, entry = nil)
    if entry.blank?
      entry = Entry.find(params[:entry_id])
    end
    uri = URI.parse(URL)
    uri.query = {"url" => entry.fully_qualified_url, "text" => entry.title}.to_query
    {text: "feedbin.sharePopup('#{uri}'); return false;"}
  end

  def share_link
    super.merge({
      url: "#{URL}?url=${url}&text=${title}",
      html_options: {"data-behavior" => "share_popup"}
    })
  end
end
