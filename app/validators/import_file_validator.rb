class ImportFileValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    path = record.file.queued_for_write[:original].path

    is_opml = false

    feeds = record.parse_opml

    feeds.each do |feed|
      if feed[:xml_url]
        is_opml = true
      end
    end

    unless is_opml
      raise "No valid outlines found in OPML"
    end
  rescue Exception => e
    record.errors[attribute] << (options[:message] || "is invalid OPML")
  end
end
