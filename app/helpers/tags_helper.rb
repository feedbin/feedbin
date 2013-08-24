module TagsHelper
  def drawer_visible?(tag_id)
    session[:tag_visibility] ||= {}
    session[:tag_visibility][tag_id.to_s] || false
  end
end
