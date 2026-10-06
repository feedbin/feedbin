class SharingService < ApplicationRecord
  belongs_to :user
  default_scope { order(Arel.sql("lower(label)")) }

  def share_link
    target = url.start_with?("http") ? "_blank" : "_self"
    {url: url, label: label, html_options: {target: target, rel: "noopener noreferrer"}}
  end

  def active?
    true
  end

  def service_id
    "custom"
  end
end
