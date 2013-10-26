Feedzirra::Feed.add_common_feed_element('_feed_id_')
Feedzirra::Feed.add_common_feed_entry_element('_public_id_')
Feedzirra::Feed.add_common_feed_entry_element('_old_public_id_')
Feedzirra::Feed.add_common_feed_entry_element('_data_')
Feedzirra::Feed.add_common_feed_entry_element('content')

class Feedzirra::Parser::ITunesRSSItem
  element :entry_id
end

ITUNES_RSS_ITEM_FIX_DATE = Time.parse('2013-07-16T15:00:00+00:00')