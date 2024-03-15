# frozen_string_literal: true

class Fixable::SuggestionComponentPreview < Lookbook::Preview
  # @param include_ignore toggle
  def default(include_ignore: false)
    render FixFeeds::SuggestionComponent.new(replaceable: Subscription.first, source: Subscription.first.feed, redirect: nil, include_ignore: include_ignore)
  end
end
