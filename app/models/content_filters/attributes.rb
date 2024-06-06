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
      doc
    end
  end
end