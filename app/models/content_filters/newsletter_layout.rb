module ContentFilters
  # Makes an HTML email lay itself out in whatever column it is put in, with
  # no script from whatever shows it. Emails are designed for a 600px window
  # and are shown in columns of any width, inside pages far wider than the
  # column, so nothing here may depend on the window.
  #
  #   1. Width media queries become container queries.
  #   2. The email is wrapped in an element that is its own query container.
  #   3. Long words and addresses may break instead of running past the edge.
  #   4. An element pinned to a pixel width gets a rule that releases the
  #      width once the container is narrower than it.
  #
  # What shows the email still owes it isolation from the page's own styles
  # (a shadow root), which markup cannot give itself.
  class NewsletterLayout < HTML::Pipeline::Filter
    WRAPPER_CLASS = "feedbin-newsletter"
    WIDTH_ATTRIBUTE = "data-feedbin-width"
    PINNABLE = %w[table td th div p img center section a span].freeze
    PINNED = "./descendant::*[#{PINNABLE.map { "local-name()='#{it}'" }.join(" or ")}][@width or @style]"

    MEDIA_RULE = /@media([^{};]*)\{/
    MEDIA_TYPE = /\A(only\s+)?(screen|all)\b\s*(and\b)?/i
    WIDTH_FEATURE = /\A\(\s*(max|min)-(?:device-)?width\s*:\s*([\d.]+px)\s*\)\z/i
    ATTRIBUTE_PIXELS = /\A\s*(\d+(?:\.\d+)?)(px)?\s*\z/
    STYLE_PIXELS = /(?:\A|;)\s*(?:min-)?width\s*:\s*(\d+(?:\.\d+)?)px\s*(?:!important\s*)?(?=;|\z)/i

    def call
      doc.xpath("./descendant-or-self::style").each { it.content = self.class.container_queries(it.content) }
      widths = pin_widths
      wrap(widths)
      doc
    end

    # A query that tests anything other than width, such as colour scheme,
    # resolution or print, is left as it is.
    def self.container_queries(css)
      css.gsub(MEDIA_RULE) do |rule|
        queries = $1.split(",").map { width_query(it) }
        next rule unless queries.any? && queries.all?
        condition = queries.one? ? queries.first : queries.map { "(#{it})" }.join(" or ")
        "@container #{condition}{"
      end
    end

    # One media query as a container condition, or nil when it is not purely
    # about width.
    def self.width_query(query)
      features = query.strip.sub(MEDIA_TYPE, "").split(/\band\b/i).map(&:strip).reject(&:empty?)
      conditions = features.map do |feature|
        match = WIDTH_FEATURE.match(feature)
        "(#{match[1].downcase}-width:#{match[2]})" if match
      end
      conditions.join(" and ") if conditions.any? && conditions.all?
    end

    private

    # Marks each element with the widest pixel width it is pinned to, by its
    # width attribute or its inline width or min-width, and returns the widths.
    def pin_widths
      doc.xpath(PINNED).filter_map { |element|
        width = [attribute_pixels(element["width"]), *style_pixels(element["style"])].max.ceil
        next if width < 1
        element[WIDTH_ATTRIBUTE] = width.to_s
        width
      }.uniq.sort
    end

    def attribute_pixels(value)
      value.to_s[ATTRIBUTE_PIXELS, 1].to_f
    end

    def style_pixels(value)
      value.to_s.scan(STYLE_PIXELS).map { it.first.to_f }
    end

    def wrap(widths)
      wrapper = doc.document.create_element("div", class: WRAPPER_CLASS, style: "container-type:inline-size;overflow-wrap:break-word")
      style = doc.document.create_element("style")
      style.content = css(widths)
      children = doc.children.to_a
      wrapper.add_child(style)
      children.each { wrapper.add_child(it) }
      doc.add_child(wrapper)
    end

    def css(widths)
      scope = ".#{WRAPPER_CLASS}"
      rules = widths.map do |width|
        pinned = %([#{WIDTH_ATTRIBUTE}="#{width}"])
        "@container (max-width:#{width}px){" \
          "#{scope} #{pinned}{width:auto !important;min-width:0 !important}" \
          "#{scope} table#{pinned}{width:100% !important}" \
          "#{scope} img#{pinned}{width:100% !important;height:auto !important}}"
      end
      "#{scope} img{max-width:100% !important;height:auto !important}" \
        "#{scope} img[width=\"1\"],#{scope} img[height=\"1\"]{display:none !important}" \
        "#{rules.join}"
    end
  end
end
