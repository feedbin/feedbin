module ApplicationHelper
  def present(object, locals = nil, klass = nil)
    klass ||= "#{object.class}Presenter".constantize
    presenter = klass.new(object, locals, self)
    yield presenter if block_given?
    presenter
  end

  def is_active?(controller, action)
    controller = [*controller]
    action = [*action]
    "active" if controller.include?(params[:controller]) && action.include?(params[:action])
  end

  def mark_selected?
    @mark_selected || false
  end

  def selected(feed_id)
    css_class = ''
    if mark_selected? && feed_id == session[:selected_feed]
      @mark_selected = false
      css_class = 'selected'
    end
    css_class
  end

  def view_mode_selected(view_mode)
    'selected' if view_mode == @user.get_view_mode
  end

  def rtl?(string)
    unless string.blank?
      rtl_test = /[\u0600-\u06FF]|[\u0750-\u077F]|[\u0590-\u05FF]|[\uFE70-\uFEFF]/m
      if string =~ rtl_test
        string = strip_tags(string)
        rtl_length = string.scan(rtl_test).size
        percentage = (rtl_length.to_f / string.length.to_f) * 100
        percentage > 50
      end
    end
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
    current_user.try(:unread_entries).try(:order, 'created_at DESC').try(:first).try(:created_at).try(:iso8601, 6)
  end


  def svg_tag(name, options={})
    options = options.symbolize_keys

    name = name.sub('.svg', '')
    options[:width], options[:height] = extract_dimensions(options.delete(:size)) if options[:size]
    options[:class] = "#{name} #{options[:class]}"

    content_tag :svg, options do
      content_tag :use, '', :"xlink:href" => "##{name}"
    end

  end

  def branch_info
    branch_name = `git rev-parse --abbrev-ref HEAD`
    " [#{branch_name.chomp}]"
  end
end
