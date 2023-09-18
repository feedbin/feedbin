module ContentFilters
  class Attributes < HTML::Pipeline::Filter
    def call
      doc.search("[style]").each do |element|
        element["style"] = ""
      end
      doc.search("[class]").each do |element|
        element["class"] = ""
      end
      doc
    end
  end
end