class DiscoveredFeed < ApplicationRecord
  before_create :set_host

  private

  def set_host
    self.host = Addressable::URI.heuristic_parse(site_url)&.host&.downcase
  end

end
