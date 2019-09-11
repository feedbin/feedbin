require "kramdown"
require "rails_autolink"

class ContentFormatter
  LEADING_CHARS = %w|
    (
    [
    {
    @
    #
    '
    "
    $
    “
  |
  TRAILING_CHARS = %w|
    )
    ]
    }
    :
    ;
    '
    "
    ?
    .
    ,
    !
    ”
  |

  def self.format!(content, entry = nil, image_proxy_enabled = true, base_url = nil)
    context = {
      whitelist: Feedbin::Application.config.whitelist,
      embed_url: Rails.application.routes.url_helpers.iframe_embeds_path,
      embed_classes: "iframe-placeholder entry-callout system-content",
    }
    filters = [HTML::Pipeline::SanitizationFilter, HTML::Pipeline::SrcFixer, HTML::Pipeline::IframeFilter]

    if ENV["CAMO_HOST"] && ENV["CAMO_KEY"] && image_proxy_enabled
      context[:asset_proxy] = ENV["CAMO_HOST"]
      context[:asset_proxy_secret_key] = ENV["CAMO_KEY"]
      context[:asset_src_attribute] = "data-camo-src"
      filters = filters << HTML::Pipeline::CamoFilter
    end

    if entry
      filters.unshift(HTML::Pipeline::AbsoluteSourceFilter)
      filters.unshift(HTML::Pipeline::AbsoluteHrefFilter)
      context[:image_base_url] = context[:href_base_url] = entry.url || entry.feed.site_url
      context[:image_subpage_url] = context[:href_subpage_url] = entry.url || ""
      if entry.feed.newsletter?
        context[:whitelist] = Feedbin::Application.config.newsletter_whitelist
      end
    elsif base_url
      filters.unshift(HTML::Pipeline::AbsoluteSourceFilter)
      filters.unshift(HTML::Pipeline::AbsoluteHrefFilter)
      context[:image_base_url] = context[:href_base_url] = base_url
      context[:image_subpage_url] = context[:href_subpage_url] = base_url
    end

    filters.unshift(HTML::Pipeline::LazyLoadFilter)

    pipeline = HTML::Pipeline.new filters, context

    result = pipeline.call(content)

    if entry && entry.archived_images?
      result[:output] = ImageFallback.new(result[:output]).add_fallbacks
    end

    result[:output].to_s
  end

  def self.absolute_source(content, entry, base_url = nil)
    filters = [HTML::Pipeline::AbsoluteSourceFilter, HTML::Pipeline::AbsoluteHrefFilter]
    context = {
      image_base_url: base_url || entry.feed.site_url,
      image_subpage_url: base_url || entry.url || "",
      href_base_url: base_url || entry.feed.site_url,
      href_subpage_url: base_url || entry.url || "",
    }
    pipeline = HTML::Pipeline.new filters, context
    result = pipeline.call(content)
    result[:output].to_s
  rescue
    content
  end

  def self.api_format(content, entry)
    filters = [HTML::Pipeline::AbsoluteSourceFilter, HTML::Pipeline::AbsoluteHrefFilter, HTML::Pipeline::ProtocolFilter]
    context = {
      image_base_url: entry.feed.site_url,
      image_subpage_url: entry.url || "",
      href_base_url: entry.feed.site_url,
      href_subpage_url: entry.url || "",
    }
    if entry.feed.newsletter?
      filters.push(HTML::Pipeline::SanitizationFilter)
      context[:whitelist] = Feedbin::Application.config.newsletter_whitelist
    end
    pipeline = HTML::Pipeline.new filters, context
    result = pipeline.call(content)
    result[:output].to_s
  rescue
    content
  end

  def self.app_format(content, entry)
    filters = [HTML::Pipeline::AbsoluteSourceFilter, HTML::Pipeline::AbsoluteHrefFilter, HTML::Pipeline::ProtocolFilter, HTML::Pipeline::ImagePlaceholderFilter]
    context = {
      image_base_url: entry.feed.site_url,
      image_subpage_url: entry.url || "",
      href_base_url: entry.feed.site_url,
      href_subpage_url: entry.url || "",
      placeholder_url: "",
      placeholder_attribute: "data-feedbin-src",
    }
    pipeline = HTML::Pipeline.new filters, context
    result = pipeline.call(content)
    result[:output].to_s
  rescue
    content
  end

  def self.evernote_format(content, entry)
    filters = [HTML::Pipeline::SanitizationFilter, HTML::Pipeline::SrcFixer, HTML::Pipeline::AbsoluteSourceFilter, HTML::Pipeline::AbsoluteHrefFilter, HTML::Pipeline::ProtocolFilter]
    context = {
      whitelist: Feedbin::Application.config.evernote_whitelist.clone,
      image_base_url: entry.feed.site_url,
      image_subpage_url: entry.url || "",
      href_base_url: entry.feed.site_url,
      href_subpage_url: entry.url || "",
    }

    pipeline = HTML::Pipeline.new filters, context
    result = pipeline.call(content)
    result[:output].to_xml
  rescue
    content
  end

  def self.summary(text, length = nil)
    decoder = HTMLEntities.new
    text = decoder.decode(text)
    text = text.chars.select(&:valid_encoding?).join

    sanitize_config = Sanitize::Config::BASIC.dup
    sanitize_config = sanitize_config.merge(remove_contents: ["script", "style", "iframe", "object", "embed", "figure"])
    text = Sanitize.fragment(text, sanitize_config)

    text = Nokogiri::HTML(text)
    text = text.search("//text()").map(&:text).join(" ").squish

    TRAILING_CHARS.each do |char|
      text = text.gsub(" #{char}", char.to_s)
    end

    LEADING_CHARS.each do |char|
      text = text.gsub("#{char} ", char.to_s)
    end

    if length
      text = text.truncate(length, separator: " ", omission: "")
    end

    text
  rescue
    nil
  end

  def self.text_email(content)
    content = Kramdown::Document.new(content).to_html
    ActionController::Base.helpers.auto_link(content)
  rescue
    content
  end
end
