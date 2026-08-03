module ContentFilters
  ALLOWED_CLASSES = %w[
    twitter-tweet
    instagram-media
    imgur-embed-pub
    kg-bookmark-card
    kg-bookmark-author
    kg-bookmark-container
    kg-bookmark-content
    kg-bookmark-description
    kg-bookmark-icon
    kg-bookmark-metadata
    kg-bookmark-publisher
    kg-bookmark-thumbnail
    kg-bookmark-title
  ]

  class Attributes < HTML::Pipeline::Filter
    def call
      doc.search("[style]").each do |element|
        element.delete("style")
      end
      doc.search("[align]").each do |element|
        element.delete("align")
      end
      doc.search("[class]").each do |element|
        classes = (element["class"] || "").split
        classes = classes & ALLOWED_CLASSES
        if classes.empty?
          element.delete("class")
        else
          element["class"] = classes.join(" ")
        end
      end
      # Loofah allows every data-* attribute through without a protocol check,
      # and Feedbin's front end dispatches on them: data-behavior, data-controller
      # and data-iframe-* all reach the app's own handlers. None of them may come
      # from the content, so they go here rather than being allow-listed. The
      # ones Feedbin sets itself are added by filters that run after this one.
      doc.search("*").each do |element|
        element.attribute_nodes.each do |attribute|
          element.delete(attribute.name) if attribute.name.start_with?("data-")
        end
      end
      doc
    end
  end
end