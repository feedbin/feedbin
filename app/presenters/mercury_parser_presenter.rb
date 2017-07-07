class MercuryParserPresenter < BasePresenter

  presents :mercury_parser

  def favicon
    if record = Favicon.find_by(host: mercury_parser.domain)
      favicon_template(record.cdn_url)
    else
      favicon_with_url(mercury_parser.domain)
    end
  end

end