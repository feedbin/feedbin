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
    feedbin.Counts.get().removeEntry(entryInfo.id, entryInfo.feed_id, 'unread')
    @applyCounts()
    entryInfo.read = true
    $("[data-entry-id=#{entryInfo.id}]").addClass('read')
    $("[data-entry-id=#{entryInfo.id}][data-behavior~=entry_info]").data('entry-info', entryInfo)

  markAsUnread: (entryInfo) ->
    feedbin.Counts.get().addEntry(entryInfo.id, entryInfo.feed_id, entryInfo.published, 'unread')
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
    $('[data-behavior~=needs_count]').each (index, element) =>
      group = $(element).data('count-group')
      groupId = $(element).data('count-group-id')

      collection = 'unread'
      if feedbin.data.viewMode == 'view_starred'
        # TODO change this to starred
        collection = 'unread'

      counts = feedbin.Counts.get().counts[collection][group]

      count = 0
      if groupId
        if (groupId of counts)
          count = counts[groupId].length
          $(element).text(count)
        if (count == 0)
          $(element).parents('li').first().addClass('zero-count')
        else
          $(element).parents('li').first().removeClass('zero-count')
      else
        count = counts.length
        $(element).text(count)
        if (count == 0)
          $(element).addClass('hide')
        else
          $(element).removeClass('hide')