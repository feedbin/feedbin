class Sparkline
  attr_reader :width, :height, :percentages, :stroke

  def initialize(width:, height:, stroke:, percentages:)
    @width = width.to_f
    @height = height.to_f
    @percentages = percentages
    @stroke = stroke
  end

  def fill
    to_attr([
      [0, height], *fill_points, [width, height]
    ])
  end

  def line
    to_attr(line_points)
  end

  def to_attr(items)
    items.map { |item| item.join(",") }.join(" ")
  end

  def fill_points
    percentages.each_with_index.map do |percentage, index|
      [x(index), y(percentage)]
    end
  end

  def line_points
    percentages.each_with_index.map do |percentage, index|
      y_position = y(percentage)
      if y_position == 0.0
        y_position = stroke_width_adjustment
      elsif y_position == height
        y_position = height - stroke_width_adjustment
      end

      x_position = x(index)
      if index == 0
        x_position = stroke_width_adjustment
      elsif index == percentages.count - 1
        x_position -= stroke_width_adjustment
      end

      [x_position, y_position]
    end
  end

  def segment_width
    @segment_width ||= width / (percentages.length - 1)
  end

  def stroke_width_adjustment
    stroke / 2
  end

  def x(index)
    (segment_width * index).round(1)
  end

  def y(percentage)
    ((1.00 - percentage) * height).round(1)
  rescue
    1.00 * (height - 1)
  end
end
