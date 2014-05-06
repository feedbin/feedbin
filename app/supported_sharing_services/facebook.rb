class Facebook < Service
  URL = 'https://www.facebook.com/sharer/sharer.php'

  def initialize(klass = nil)
    @klass = klass
  end

  def share(params)
    entry = Entry.find(params[:entry_id])
    uri = URI.parse(URL)
    uri.query = { 'u' => entry.fully_qualified_url, 'display' => 'popup' }.to_query
    {text: render_popover_template(uri.to_s)}
  end

end