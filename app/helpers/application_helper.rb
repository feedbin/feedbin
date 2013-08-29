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

  def hide_count(count)
    if count == 0
      ' hide'
    else
      ''
    end
  end

  def mark_selected?
    @mark_selected || false
  end

  def selected(feed_id)
    if mark_selected? && feed_id == session[:selected_feed]
      @mark_selected = false
      'selected'
    end
  end

  def view_mode_selected(view_mode)
    saved_view_mode = session[:view_mode]
    if saved_view_mode
      'selected' if view_mode == saved_view_mode
    else
      'selected' if view_mode == 'view_unread'
    end
  end

  def link_to_add_fields(name, f, association)
    new_object = f.object.send(association).klass.new
    id = new_object.object_id
    fields = f.fields_for(association, new_object, child_index: id) do |builder|
      render(association.to_s.singularize + "_fields", f: builder)
    end
    link_to(name, '#', class: "button button-text", data: {id: id, fields: fields.gsub("\n", ""), behavior: 'add_fields'})
  end

end
