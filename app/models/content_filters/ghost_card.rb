module ContentFilters
  class GhostCard < HTML::Pipeline::Filter
    CARDS = "./descendant::*[contains(concat(' ', normalize-space(@class), ' '), ' kg-bookmark-card ')]"

    def call
      doc.xpath(CARDS).each do |element|
        element["class"] = [element["class"], "system-content"].join(" ")
      end
      doc
    end
  end
end
