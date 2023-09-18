module ContentFilters
  ALLOWED_CLASSES = ["twitter-tweet", "instagram-media", "imgur-embed-pub"]

  class Attributes < HTML::Pipeline::Filter
    def call
      doc.search("[style]").each do |element|
        element["style"] = ""
      end
      doc.search("[class]").each do |element|
        classes = (element["class"] || "").split
        classes = classes & ALLOWED_CLASSES
        element["class"] = classes.join(" ")
      end
      doc
    end
  end
end