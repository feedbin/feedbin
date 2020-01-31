class Sparkline

  attr_reader :width, :height, :percentages

  def initialize(width, height, percentages)
    @width = width
    @height = height
    @percentages = percentages
  end

  def fill
    to_attr([
      [0,0],
      *fill_points,
      [width, 0]
    ])
  end

  def line
    to_attr(line_points)
  end

  def to_attr(items)
    items.map {|item| item.join(",")}.join(" ")
  end

  def fill_points
    percentages.each_with_index.map do |percentage, index|
      [x(index), y(percentage)]
    end
  end

  def line_points
    percentages.each_with_index.map do |percentage, index|
      result = y(percentage)
      if result == 0.0
        result = 1.0
      end

      result2 = x(index)
      if index == 0
        result2 = 1.0
      elsif index == percentages.count - 1
        result2 = result2 - 1.0
      end
      [result2, result]
    end
  end

  def x(index)
    (width.to_f / (percentages.length - 1)).to_f * index
  end

  def y(percentage)
    ((1.00 - percentage.to_f) * (height - 1)).to_i
  end
end