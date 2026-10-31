# for example the controls on each image on https://www.thealgorithmicbridge.com
module ContentFilters
  class FigureControls < HTML::Pipeline::Filter
    # svg is namespaced in an HTML5 parse, so it is matched by local name.
    CONTROLS = "./descendant::figure" \
      "//*[contains(concat(' ', normalize-space(@class), ' '), ' image-link-expand ')]" \
      "//*[local-name()='svg']"

    def call
      doc.xpath(CONTROLS).each(&:remove)
      doc
    end
  end
end
