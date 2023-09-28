module ContentFilters
  ALLOWED_CLASSES = ["twitter-tweet", "instagram-media", "imgur-embed-pub"]

  class Attributes < HTML::Pipeline::Filter
    def call
      doc.search("[style]").each do |element|
        element.delete("style")
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