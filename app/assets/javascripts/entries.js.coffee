window.feedbin ?= {}

jQuery ->
  new feedbin.EntriesPager()
  feedbin.CountInstance = new feedbin.Count()

class feedbin.EntriesPager
  constructor: ->
    @container = $('.entries')
    @container.on('scroll', @check)

  check: =>
    url = $('.pagination .next_page').attr('href')
    if @nearBottom() && url
      @container.unbind('scroll', @check)
      $.getScript url, =>
        @container.on('scroll', @check)

  nearBottom: =>
    height = @container.prop('scrollHeight') - @container.prop('offsetHeight')
    height - @container.scrollTop() < 1500

class feedbin.Count
  updateCount: (feed, tags, action = 'decrement') ->
    @action = action
    selectors = ['[data-behavior~=all_unread]', "[data-feed-id=#{feed}]"]
    $.each tags, (index, tag_id) =>
      selectors.push "[data-tag-id=#{tag_id}]"
    targets = $(selectors.join(', '))
    @performUpdate target for target in targets

  updateStarredCount: (action) ->
    @action = action
    @performUpdate '[data-behavior~=starred]'

  performUpdate: (target) ->
    countWrap = $(target).find('.count').first()
    previousCount = countWrap.text() * 1
    if @action == 'increment'
      newCount = previousCount + 1
    else
      newCount = previousCount - 1
    if newCount >= 0
      countWrap.text(newCount)
      if newCount == 0
        if feedbin.data.viewMode == 'view_unread'
          feedbin.hideQueue.push $(target).data('feed-id')
        countWrap.addClass('hide')
      else
        countWrap.removeClass('hide')
        # Remove from hidequeue if number goes back up
        $.each feedbin.hideQueue, (index, feed_id) ->
          if $(target).data('feed-id') == feed_id
            feedbin.hideQueue.remove(index)
