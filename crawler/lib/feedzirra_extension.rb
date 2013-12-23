Feedzirra::Feed.add_common_feed_element('_feed_id_')
Feedzirra::Feed.add_common_feed_entry_element('_public_id_')
Feedzirra::Feed.add_common_feed_entry_element('_old_public_id_')
Feedzirra::Feed.add_common_feed_entry_element('_data_')
Feedzirra::Feed.add_common_feed_entry_element('content')

Feedzirra::Parser::Atom.preprocess_xml = true