# Infinite scrolling breaks if the list changes while the user pages through
# it. Two mechanisms keep pages stable, and every page link carries both:
#
# - The anchor caps the list at the newest entry that existed when the first
#   page was loaded, so entries arriving mid-session can't shift pages.
#   New entries appear after a refresh, which starts a new anchor.
#
# - The cursor records the sort position of the last entry the client
#   received, so the next page resumes from that exact position. Rows deleted
#   behind the reader (entries marked read as the user moves through them)
#   can't shift or exhaust later pages the way an offset would.
module StablePagination
  extend ActiveSupport::Concern

  included do
    helper_method :pagination_link_params
  end

  private

  # Loads one stable page of entries. Applies the anchor, orders by the
  # cursor keys, slices at the requested position, and records the cursor for
  # the next page's links. Ordering lives here rather than at the call sites
  # because the ORDER BY must match the cursor comparison exactly.
  #
  # Sets @page_query for will_paginate and @page_cursor for
  # pagination_link_params, and returns the page of entries.
  def entries_page(scope, sort: "DESC")
    direction = (sort == "ASC") ? "ASC" : "DESC"
    scope = pagination_anchor(scope).order(Arel.sql("published #{direction}, entry_id #{direction}"))
    @page_query = cursor_slice(scope, direction)
    rows = @page_query.pluck(:entry_id, :published)
    @page_cursor = next_page_cursor(rows)
    Entry.in_order_of(:id, rows.map(&:first)).entries_list
  end

  def pagination_anchor(scope, column: scope.arel_table[:entry_id])
    @anchor ||= if params[:page_anchor].present?
      params[:page_anchor].to_i
    else
      Entry.maximum(:id)
    end
    @anchor ? scope.where(column.lteq(@anchor)) : scope
  end

  def cursor_slice(scope, direction)
    if params[:cursor_published].present? && params[:cursor_entry_id].present?
      operator = (direction == "ASC") ? ">" : "<"
      published = Time.zone.at(params[:cursor_published].to_r)
      scope.where("(published, entry_id) #{operator} (?, ?)", published, params[:cursor_entry_id].to_i).page(nil)
    else
      scope.page(params[:page])
    end
  end

  def next_page_cursor(rows)
    entry_id, published = rows.last
    if entry_id && published
      {cursor_published: published.strftime("%s.%6N"), cursor_entry_id: entry_id}
    end
  end

  def pagination_link_params
    link_params = {}
    link_params[:page_anchor] = @anchor if @anchor
    link_params.merge!(@page_cursor) if @page_cursor
    link_params
  end
end
