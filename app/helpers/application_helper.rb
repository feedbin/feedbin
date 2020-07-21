module ApplicationHelper
  def present(object, locals = nil, klass = nil)
    klass ||= "#{object.class}Presenter".constantize
    presenter = klass.new(object, locals, self)
    yield presenter if block_given?
    presenter
  end

  def native?
    request.user_agent&.include?("TurbolinksFeedbin")
  end

  def is_active?(controller, action)
    controller = [*controller]
    action = [*action]
    "active" if controller.include?(params[:controller]) && action.include?(params[:action])
  end

  def rtl?(string)
    unless string.blank?
      rtl_test = /[\u0600-\u06FF]|[\u0750-\u077F]|[\u0590-\u05FF]|[\uFE70-\uFEFF]/m
      if string&.match?(rtl_test)
        string = strip_tags(string)
        rtl_length = string.scan(rtl_test).size
        percentage = (rtl_length.to_f / string.length.to_f) * 100
        percentage > 50
      end
    end
  end

  def json_array(&block)
    raw "[#{yield}]"
  end

  def rtl(string)
    if rtl?(string)
      'dir="rtl"'.html_safe
    end
  end

  def get_protocol
    Feedbin::Application.config.force_ssl ? "https:" : "http:"
  end

  def last_unread_date
    current_user.try(:unread_entries).try(:order, "created_at DESC").try(:first).try(:created_at).try(:iso8601, 6)
  end

  def get_icon(name)
    name = name.sub(".svg", "")
    icon = Feedbin::Application.config.icons[name]
    unless icon
      file = "#{Rails.root}/app/assets/svg/#{name}.svg"
      if File.file?(file)
        icon = Feedbin::Application.config.icons[name] = SvgIcon.new_from_file(file)
      end
    end
    icon
  end

  def icon_exists?(name)
    get_icon(name).present?
  end

  def svg_tag(name, options = {})
    options = options.symbolize_keys

    name = name.sub(".svg", "")
    options.delete(:size)

    icon = get_icon(name)

    unless icon
      raise "Icon missing #{name}"
    end

    options[:width] = icon.width
    options[:height] = icon.height

    options[:class] = [name, options[:class]].compact.join(" ")

    inline = options.delete(:inline)

    content_tag :svg, options do
      if inline
        icon.markup.html_safe
      else
        content_tag :use, "", "href": "##{name}"
      end
    end
  end

  def branch_info
    branch_name = `git rev-parse --abbrev-ref HEAD`
    " [#{branch_name.chomp}]"
  end

  def favicon_with_host(host)
    record = Favicon.find_by(host: host)
    if record && record.url.present?
      favicon_template(record.cdn_url)
    else
      favicon_url = favicon_service_url(host)
      favicon_template(favicon_url)
    end
  end

  def favicon_template(favicon_url)
    content_tag :span, "", class: "favicon-wrap" do
      content_tag(:span, "", class: "favicon", style: "background-image: url(#{favicon_url});")
    end
  end

  def favicon_service_url(host)
    uri = URI::HTTP.build(
      scheme: "https",
      host: "www.google.com",
      path: "/s2/favicons",
      query: {domain: host}.to_query
    )
    uri.scheme = "https"
    uri.to_s
  end

  def image_tag_with_fallback(fallback, *image_args)
    options = image_args.length > 1 ? image_args.last : {}
    options["onerror"] = "this.onerror=null;this.src='%s';" % fallback
    image_tag(image_args.first, options)
  end

  def pretty_url(url)
    url && url.sub("http://", "").sub("https://", "").gsub(/\/$/, "").truncate(40, omission: "...")
  end

  def camo_link(url)
    options = {
      asset_proxy: ENV["CAMO_HOST"],
      asset_proxy_secret_key: ENV["CAMO_KEY"]
    }
    pipeline = HTML::Pipeline::CamoFilter.new(nil, options, nil)
    pipeline.asset_proxy_url(url.to_s)
  end

  def business_address(format = nil)
    address = ENV["BUSINESS_ADDRESS"] || ""
    address = address.split("\n")
    if format == :text
      address.join("\n")
    else
      address.join("<br>").html_safe
    end
  end

  def toggle_switch(options = {})
    css_class = options.delete(:class)
    defaults = {
      class: "switch #{css_class}"
    }
    content_tag :span, defaults.merge(options) do
      content_tag :span, class: "switch-inner" do
        svg_tag "icon-check"
      end
    end
  end

  def radio_button_control
    content_tag :span, class: "radio-button" do
      content_tag :span, class: "radio-button-inner" do
      end
    end
  end

  def short_number(number)
    number_to_human(number, format: "%n%u", precision: 2, units: {thousand: "K", million: "M", billion: "B"})
  end

  def xml_format(content, entry)
    raw(ContentFormatter.absolute_source(content, entry))
  end
end
