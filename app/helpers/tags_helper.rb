module TagsHelper
  def drawer_visible?(tag_id)
    current_user.tag_visibility[tag_id.to_s] || false
  end
end
