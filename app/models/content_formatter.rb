class ContentFormatter
  ALLOWLIST_BASE = {}.tap do |hash|
    hash[:elements] = %w[
      h1 h2 h3 h4 h5 h6 h7 h8 br b i strong em a pre code img tt div ins del sup sub
      p ol ul table thead tbody tfoot blockquote dl dt dd kbd q samp var hr ruby rt
      rp li tr td th s strike summary details figure figcaption audio video source
      small iframe
    ]

    hash[:attributes] = {
      "a" => ["href"],
      "img" => ["src", "longdesc"],
      "div" => ["itemscope", "itemtype"],
      "blockquote" => ["cite"],
      "del" => ["cite"],
      "ins" => ["cite"],
      "q" => ["cite"],
      "source" => ["src"],
      "video" => ["src", "poster", "playsinline", "loop", "muted", "controls", "preload"],
      "audio" => ["src"],
      "td" => ["align"],
      "th" => ["align"],
      "iframe" => ["src", "width", "height"],
      :all => %w[
        abbr accept accept-charset accesskey action alt axis border cellpadding
        cellspacing char charoff charset checked clear cols colspan color compact
        coords datetime dir disabled enctype for frame headers height hreflang hspace
        ismap label lang maxlength media method multiple name nohref noshade nowrap
        open prompt readonly rel rev rows rowspan rules scope selected shape size span
        start summary tabindex target title type usemap valign value vspace width
        itemprop id
      ]
    }

    hash[:protocols] = {
      "a" => {
        "href" => ["http", "https", "mailto", :relative]
      },
      "blockquote" => {
        "cite" => ["http", "https", :relative]
      },
      "del" => {
        "cite" => ["http", "https", :relative]
      },
      "ins" => {
        "cite" => ["http", "https", :relative]
      },
      "q" => {
        "cite" => ["http", "https", :relative]
      },
      "img" => {
        "src" => ["http", "https", :relative, "data"],
        "longdesc" => ["http", "https", :relative]
      },
      "video" => {
        "src" => ["http", "https"],
        "poster" => ["http", "https"]
      },
      "audio" => {
        "src" => ["http", "https"]
      }
    }

    hash[:remove_contents] = %w[script style iframe object embed]
  end

  ALLOWLIST_DEFAULT = ALLOWLIST_BASE.clone.tap do |hash|
    transformers = Transformers.new
    hash[:transformers] = [transformers.class_allowlist, transformers.table_elements, transformers.top_level_li, transformers.video, transformers.links]
  end

  ALLOWLIST_NEWSLETTER = ALLOWLIST_BASE.clone.tap do |hash|
    hash[:elements] = hash[:elements] - %w[table thead tbody tfoot tr td]
  end

  ALLOWLIST_EVERNOTE = {
    elements: %w[
      a abbr acronym address area b bdo big blockquote br caption center cite code col colgroup dd
      del dfn div dl dt em font h1 h2 h3 h4 h5 h6 hr i img ins kbd li map ol p pre q s samp small
      strike strong sub sup table tbody td tfoot th thead tr tt u ul var xmp
    ],
    remove_contents: ["script", "style", "iframe", "object", "embed", "title"],
    attributes: {
        "a"     => ["href"],
        "img"   => ["src", "width", "height", "alt"],
        "ol"    => Sanitize::Config::RELAXED[:attributes]["ol"],
        "ul"    => Sanitize::Config::RELAXED[:attributes]["ul"],
        "table" => Sanitize::Config::RELAXED[:attributes]["table"],
        "td"    => Sanitize::Config::RELAXED[:attributes]["td"],
        "th"    => Sanitize::Config::RELAXED[:attributes]["th"]
    },
    protocols: {
      "a" => {"href" => ["http", "https", :relative]},
      "img" => {"src" => ["http", "https", :relative]}
    }
  }

  SANITIZE_BASIC = Sanitize::Config.merge(Sanitize::Config::BASIC, remove_contents: ["script", "style", "iframe", "object", "embed", "figure"])

  def self.format!(*args)
    new._format!(*args)
  end

  def _format!(content, entry = nil, image_proxy_enabled = true, base_url = nil)
    context = {
      scrub_mode: :default,
      embed_url: Rails.application.routes.url_helpers.iframe_embeds_path,
      embed_classes: "iframe-placeholder entry-callout system-content"
    }
    if entry && entry.feed.newsletter?
      context[:scrub_mode] = :newsletter
    end

    filters = [HTML::Pipeline::SmileyFilter, ContentFilters::Scrub, ContentFilters::Attributes, HTML::Pipeline::SrcFixer, HTML::Pipeline::IframeFilter]

    if ENV["CAMO_HOST"] && ENV["CAMO_KEY"] && image_proxy_enabled
      context[:asset_proxy] = ENV["CAMO_HOST"]
      context[:asset_proxy_secret_key] = ENV["CAMO_KEY"]
      context[:asset_src_attribute] = "data-camo-src"
      filters.push(HTML::Pipeline::CamoFilter)
    end

    if entry || base_url
      filters.unshift(HTML::Pipeline::AbsoluteSourceFilter)
      filters.unshift(HTML::Pipeline::AbsoluteHrefFilter)

      context[:image_base_url]    = base_url || entry.base_url
      context[:image_subpage_url] = base_url || entry.fully_qualified_url || ""
      context[:href_base_url]     = base_url || entry.base_url
      context[:href_subpage_url]  = base_url || entry.fully_qualified_url || ""
    end

    if entry&.newsletter_from =~ /@substack.com/
      filters.unshift(ContentFilters::Substack)
    end

    filters.unshift(HTML::Pipeline::LazyLoadFilter)

    pipeline = HTML::Pipeline.new filters, context

    result = pipeline.call(content)

    if entry&.archived_images?
      result[:output] = ImageFallback.new(result[:output]).add_fallbacks
    end

    result[:output].to_s
  end

  def self.newsletter_format(*args)
    new._newsletter_format(*args)
  end

  def _newsletter_format(content)
    context = {
      whitelist: Sanitize::Config::RELAXED
    }
    filters = [HTML::Pipeline::SanitizationFilter]

    if ENV["CAMO_HOST"] && ENV["CAMO_KEY"]
      context[:asset_proxy] = ENV["CAMO_HOST"]
      context[:asset_proxy_secret_key] = ENV["CAMO_KEY"]
      context[:asset_src_attribute] = "data-camo-src"
      filters = filters << HTML::Pipeline::CamoFilter
    end

    pipeline = HTML::Pipeline.new filters, context

    result = pipeline.call(content)

    result[:output].to_s
  end

  def self.absolute_source(*args)
    new._absolute_source(*args)
  end

  def _absolute_source(content, entry, base_url = nil)
    filters = [HTML::Pipeline::AbsoluteSourceFilter, HTML::Pipeline::AbsoluteHrefFilter]
    context = {
      image_base_url:    base_url || entry.base_url,
      image_subpage_url: base_url || entry.fully_qualified_url || "",
      href_base_url:     base_url || entry.base_url,
      href_subpage_url:  base_url || entry.fully_qualified_url || ""
    }
    pipeline = HTML::Pipeline.new filters, context
    result = pipeline.call(content)
    result[:output].to_s
  rescue
    content
  end

  def self.api_format(*args)
    new._api_format(*args)
  end

  def _api_format(content, entry)
    filters = [HTML::Pipeline::AbsoluteSourceFilter, HTML::Pipeline::AbsoluteHrefFilter, HTML::Pipeline::ProtocolFilter, ContentFilters::Scrub, ContentFilters::Attributes]
    context = {
      scrub_mode: :default,
      image_base_url: entry.base_url,
      image_subpage_url: entry.fully_qualified_url || "",
      href_base_url: entry.base_url,
      href_subpage_url: entry.fully_qualified_url || ""
    }

    if entry.feed.newsletter?
      context[:scrub_mode] = :newsletter
    end
    pipeline = HTML::Pipeline.new filters, context
    result = pipeline.call(content)
    result[:output].to_s
  rescue
    content
  end

  def self.app_format(*args)
    new._app_format(*args)
  end

  def _app_format(content, entry)
    filters = [HTML::Pipeline::AbsoluteSourceFilter, HTML::Pipeline::AbsoluteHrefFilter, HTML::Pipeline::ProtocolFilter, HTML::Pipeline::ImagePlaceholderFilter]
    context = {
      image_base_url: entry.base_url,
      image_subpage_url: entry.fully_qualified_url || "",
      href_base_url: entry.base_url,
      href_subpage_url: entry.fully_qualified_url || "",
      placeholder_url: "",
      placeholder_attribute: "data-feedbin-src"
    }
    pipeline = HTML::Pipeline.new filters, context
    result = pipeline.call(content)
    result[:output].to_s
  rescue
    content
  end

  def self.evernote_format(*args)
    new._evernote_format(*args)
  end

  def _evernote_format(content, entry)
    filters = [HTML::Pipeline::SanitizationFilter, HTML::Pipeline::SrcFixer, HTML::Pipeline::AbsoluteSourceFilter, HTML::Pipeline::AbsoluteHrefFilter, HTML::Pipeline::ProtocolFilter]
    context = {
      whitelist: ALLOWLIST_EVERNOTE,
      image_base_url: entry.base_url,
      image_subpage_url: entry.fully_qualified_url || "",
      href_base_url: entry.base_url,
      href_subpage_url: entry.fully_qualified_url || ""
    }

    pipeline = HTML::Pipeline.new filters, context
    result = pipeline.call(content)
    result[:output].to_xml
  rescue
    content
  end

  def self.summary(*args)
    new._summary(*args)
  end

  def _summary(content, length = nil)
    return "" if content.nil?

    content = HTML::Pipeline.new([ContentFilters::Scrub])
      .call(content)[:output]
      .to_text(encode_special_chars: false).gsub(/\s+/, " ").squish
    content = content.truncate(length, separator: " ", omission: "") if length
    content
  rescue HTML::Pipeline::Filter::InvalidDocumentException
    ""
  end

  def self.text_email(*args)
    new._text_email(*args)
  end

  def _text_email(content)
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML.new(hard_wrap: true), autolink: true)
    content = markdown.render(content)
    Sanitize.fragment(content, ALLOWLIST_DEFAULT).html_safe
  rescue
    content
  end
end
