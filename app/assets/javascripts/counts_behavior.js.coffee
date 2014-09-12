window.feedbin ?= {}

jQuery ->
  new feedbin.CountsBehavior()

class feedbin.CountsBehavior
  constructor: ->
    @hideQueue = []
    @applyCounts(false)
    $(document).on('click', '[data-behavior~=change_view_mode]', @changeViewMode)
    $(document).on('click', '[data-behavior~=show_entry_content]', @showEntryContent)
    $(document).on('ajax:beforeSend', '[data-behavior~=toggle_read]', @toggleRead)
    $(document).on('ajax:beforeSend', '[data-behavior~=toggle_starred]', @toggleStarred)
    $(document).on('click', '[data-behavior~=show_entries]', @processHideQueue)

  changeViewMode: (event) =>
    @hideQueue = []
    element = $(event.currentTarget)
    $('[data-behavior~=change_view_mode]').removeClass('selected')
    element.addClass('selected')

    feedbin.data.viewMode = element.data('view-mode')

    $('body').removeClass('view_all view_unread view_starred');
    $('body').addClass(feedbin.data.viewMode);
    @applyCounts(false)

    if feedbin.openFirstItem
      $('[data-behavior~=feeds_target] li:visible').first().find('a')[0].click();
      feedbin.openFirstItem = false;

  showEntryContent: (event) =>
    clearTimeout feedbin.recentlyReadTimer
    container = $(event.currentTarget)
    entryInfo = $(container).data('entry-info')
    if !entryInfo.read
      $.post $(container).data('mark-as-read-path')
      feedbin.recentlyReadTimer = setTimeout ( ->
        $.post $(container).data('recently-read-path')
      ), 10000
      feedbin.Counts.get().removeEntry(entryInfo.id, entryInfo.feed_id, 'unread')
      @mark(entryInfo, 'read')
    @applyStarred()

  toggleRead: (event, xhr) =>
    entryInfo = $('[data-behavior~=selected_entry_data]').data('entry-info')
    if entryInfo.read
      feedbin.Counts.get().addEntry(entryInfo.id, entryInfo.feed_id, entryInfo.published, 'unread')
      @unmark(entryInfo, 'read')
    else
      feedbin.Counts.get().removeEntry(entryInfo.id, entryInfo.feed_id, 'unread')
      @mark(entryInfo, 'read')

  mark: (entryInfo, property) ->
    @applyCounts(true)
    entryInfo[property] = true
    $("[data-entry-id=#{entryInfo.id}]").addClass(property)
    $("[data-entry-id=#{entryInfo.id}][data-behavior~=entry_info]").data('entry-info', entryInfo)

  unmark: (entryInfo, property) ->
    @applyCounts(true)
    entryInfo[property] = false
    $("[data-entry-id=#{entryInfo.id}]").removeClass(property)
    $("[data-entry-id=#{entryInfo.id}][data-behavior~=entry_info]").data('entry-info', entryInfo)

  applyCounts: (useHideQueue) ->
    $('[data-behavior~=needs_count]').each (index, countContainer) =>
      group = $(countContainer).data('count-group')
      groupId = $(countContainer).data('count-group-id')

      collection = 'unread'
      console.log 'feedbin.data.viewMode', feedbin.data.viewMode
      if feedbin.data.viewMode == 'view_starred'
        collection = 'starred'

      counts = feedbin.Counts.get().counts[collection][group]
      countWas = $(countContainer).text() * 1
      count = 0

      if groupId
        if groupId of counts
          count = counts[groupId].length
      else
        count = counts.length
      $(countContainer).text(count)

      if count == 0
        $(countContainer).addClass('hide')
      else
        $(countContainer).removeClass('hide')

      if groupId
        container = $(countContainer).parents('li').first()
        if useHideQueue
          feedId = $(container).data('feed-id')
          if @countReachedZero(count, countWas)
            @hideQueue.push(feedId)
          if @countWentUpFromZero(count, countWas)
            index = @hideQueue.indexOf(feedId)
            if index > -1
              @hideQueue.splice(index, 1);
            container.removeClass('zero-count')
        else
          container.removeClass('zero-count')
          if count == 0
            container.addClass('zero-count')

  countReachedZero: (count, countWas) ->
    count == 0 && countWas > 0

  countWentUpFromZero: (count, countWas) ->
    countWas == 0 && count > 0

  toggleStarred: (event, xhr) =>
    entryInfo = $('[data-behavior~=selected_entry_data]').data('entry-info')
    if entryInfo.starred
      feedbin.Counts.get().removeEntry(entryInfo.id, entryInfo.feed_id, 'starred')
      @unmark(entryInfo, 'starred')
    else
      feedbin.Counts.get().addEntry(entryInfo.id, entryInfo.feed_id, entryInfo.published, 'starred')
      @mark(entryInfo, 'starred')

  applyStarred: ->
    entryInfo = $('[data-behavior~=selected_entry_data]').data('entry-info')
    if entryInfo
      starred = feedbin.Counts.get().counts.starred.all
      if _.contains(starred, entryInfo.id)
        @mark(entryInfo, 'starred')

  processHideQueue: =>
    $.each @hideQueue, (index, feed_id) ->
      if feed_id != undefined
        item = $("[data-feed-id=#{feed_id}]", '.feeds')
        $(item).addClass('zero-count')
    @hideQueue = []
    return
