class ContentFormatter

  def self.format!(content, entry = nil)
    whitelist = HTML::Pipeline::SanitizationFilter::WHITELIST.clone
    transformers = [iframe_whitelist] + whitelist[:transformers]
    whitelist[:transformers] = transformers

    context = {
      whitelist: whitelist
    }
    filters = [HTML::Pipeline::SanitizationFilter]

    if ENV['CAMO_HOST'] && ENV['CAMO_KEY']
      context[:asset_proxy] = ENV['CAMO_HOST']
      context[:asset_proxy_secret_key] = ENV['CAMO_KEY']
      filters = filters << HTML::Pipeline::CamoFilter
    end

    if entry
      filters.unshift(HTML::Pipeline::AbsoluteSourceFilter)
      filters.unshift(HTML::Pipeline::AbsoluteHrefFilter)
      context[:image_base_url] = context[:href_base_url] = entry.feed.site_url
      context[:image_subpage_url] = context[:href_subpage_url] = entry.url
    end

    pipeline = HTML::Pipeline.new filters, context

    result = pipeline.call(content)
    result[:output].to_s
  end

  def self.absolute_source(content, entry)
    filters = [HTML::Pipeline::AbsoluteSourceFilter, HTML::Pipeline::AbsoluteHrefFilter]
    context = {
      image_base_url: entry.feed.site_url,
      image_subpage_url: entry.url,
      href_base_url: entry.feed.site_url,
      href_subpage_url: entry.url
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
      image_subpage_url: entry.url,
      href_base_url: entry.feed.site_url,
      href_subpage_url: entry.url
    }
    pipeline = HTML::Pipeline.new filters, context
    result = pipeline.call(content)
    result[:output].to_s
  rescue
    content
  end

  def self.summary(content)
    sanitize_config = Sanitize::Config::RELAXED.dup
    sanitize_config = sanitize_config.merge(remove_contents: ['script', 'style', 'iframe', 'object', 'embed'])
    content = Sanitize.clean(content, sanitize_config)
    ApplicationController.helpers.sanitize(content, tags: []).truncate(86, :separator => " ").squish
  rescue
    ''
  end

  def self.iframe_whitelist
    lambda { |env|
      node      = env[:node]
      node_name = env[:node_name]
      source    = node['src']

      if node_name != 'iframe' || env[:is_whitelisted] || !node.element? || source.nil?
        return
      end

      allowed_hosts = [
        /^
          (?:https?:\/\/|\/\/)
          (?:www\.)?
          (?:youtube\.com|youtu\.be|youtube-nocookie\.com)
        /x,
        /^
          (?:https?:\/\/|\/\/)
          (?:www\.|player\.)?
          (?:vimeo\.com)
        /x,
        /^
          (?:https?:\/\/|\/\/)
          (?:www\.)?
          (?:kickstarter\.com)
        /x,
        /^
          (?:https?:\/\/|\/\/)
          (?:embed\.spotify\.com)
        /x,
        /^
          (?:https?:\/\/|\/\/)
          (?:w\.soundcloud\.com)
        /x,
        /^
          (?:https?:\/\/|\/\/)
          (?:view\.vzaar\.com)
        /x,
        /^
          (?:https?:\/\/|\/\/)
          (?:vine\.co)
        /x,
        /^
          (?:https?:\/\/|\/\/)
          (?:e\.)?
          (?:infogr\.am)
        /x,
        /^
          (?:https?:\/\/|\/\/)
          (?:mpora\.com)
        /x
      ]

      source_allowed = false
      allowed_hosts.each do |host|
        if source =~ host
          source_allowed = true
        end
      end

      return unless source_allowed

      # Force protocol relative url
      node['src'] = source.gsub(/^https?:?/, '')

      # Strip attributes
      Sanitize.clean_node!(node, {
        :elements => %w[iframe],
        :attributes => {
          'iframe'  => %w[allowfullscreen frameborder height src width]
        }
      })

      {:node_whitelist => [node]}
    }
  end

end