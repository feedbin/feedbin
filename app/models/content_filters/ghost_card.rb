module ContentFilters
  class GhostCard < HTML::Pipeline::Filter
    def call
      doc.search(".kg-bookmark-card").each do |element|
        element["class"] = [element["class"], "system-content"].join(" ")
      end
      doc
    end
  end
end