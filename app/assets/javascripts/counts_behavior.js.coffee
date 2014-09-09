window.feedbin ?= {}

jQuery ->
  new feedbin.CountsBehavior()

class feedbin.CountsBehavior
  constructor: ->
    $(document).on('click', '[data-behavior~=show_entry_content]', @showEntryContent)
    $(document).on('ajax:beforeSend', '[data-behavior~=toggle_read]', @toggleRead)
    @applyCounts()

  showEntryContent: (event) =>
    clearTimeout feedbin.recentlyReadTimer
    container = $(event.currentTarget)
    entryInfo = $(container).data('entry-info')
    if !entryInfo.read
      $.post $(container).data('mark-as-read-path')
      feedbin.recentlyReadTimer = setTimeout ( ->
        $.post $(container).data('recently-read-path')
      ), 10000
      @markAsRead(entryInfo)

  toggleRead: (event, xhr) =>
    entryInfo = $('[data-behavior~=selected_entry_data]').data('entry-info')
    if entryInfo.read
      @markAsUnread(entryInfo)
    else
      @markAsRead(entryInfo)

  markAsRead: (entryInfo) ->
    feedbin.Counts.get().markEntryRead(entryInfo.id, entryInfo.feed_id)
    @applyCounts()
    entryInfo.read = true
    $("[data-entry-id=#{entryInfo.id}]").addClass('read')
    $("[data-entry-id=#{entryInfo.id}][data-behavior~=entry_info]").data('entry-info', entryInfo)

  markAsUnread: (entryInfo) ->
    feedbin.Counts.get().markEntryUnread(entryInfo.id, entryInfo.feed_id, entryInfo.published)
    @applyCounts()
    entryInfo.read = false
    $("[data-entry-id=#{entryInfo.id}]").removeClass('read')
    $("[data-entry-id=#{entryInfo.id}][data-behavior~=entry_info]").data('entry-info', entryInfo)

  setCountCollection: (element, count) ->
    countContainer = $('> .feed-link .count', element)
    countContainer.text(count)
    if count == 0
      countContainer.addClass('hide')
    else
      countContainer.removeClass('hide')

  setCount: (element, count) ->
    countContainer = $('> .feed-link .count', element)
    countContainer.text(count)
    if count == 0
      $(element).addClass('hide')
    else
      $(element).removeClass('hide')

  applyCounts: ->
    $('[data-count-type]').each (index, element) =>
      counts = feedbin.Counts.get().counts.unread.all
      feedCounts = feedbin.Counts.get().counts.unread.byFeed
      tagCounts = feedbin.Counts.get().counts.unread.byTag
      countType = $(element).data('count-type')
      count = 0

      if countType == 'feed'
        feedId = $(element).data('feed-id')
        if (feedId of feedCounts)
          count = feedCounts[feedId].length
        @setCount(element, count)

      if countType == 'tag'
        tagId = $(element).data('tag-id')
        if (tagId of tagCounts)
          count = tagCounts[tagId].length
        @setCount(element, count)

      if countType == 'unread'
        count = counts.length
        @setCountCollection(element, count)

      if countType == 'starred'
        @setCountCollection(element, 0)

      if countType == 'recently_read'
        @setCountCollection(element, 0)
