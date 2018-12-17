window.feedbin ?= {}

feedbin.hideQueue = []

feedbin.updateTitle = () ->
  title = "Feedbin"
  if feedbin.data && feedbin.data.show_unread_count && feedbin.data.viewMode != 'view_starred'
    count = $('[data-behavior~=all_unread]').first().find('.count').text() * 1
    if count == 0
      title = "Feedbin"
    else if count >= 1000
      title = "Feedbin (1,000+)"
    else
      title = "Feedbin (#{count})"

    docTitle = $('title')
    docTitle.text(title) unless docTitle.text() is title

feedbin.applyCounts = (useHideQueue) ->
  $('[data-behavior~=needs_count]').each (index, countContainer) =>
    group = $(countContainer).data('count-group')
    groupId = $(countContainer).data('count-group-id')
    collection = $(countContainer).data('count-collection')
    countHide = $(countContainer).data('count-hide') == 'on'

    if !collection
      collection = 'unread'
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

    if groupId || countHide
      container = $(countContainer).parents('li').first()
      feedId = $(container).data('feed-id')
      if useHideQueue
        if count == 0 && countWas > 0
          feedbin.hideQueue.push(feedId)
        if countWas == 0 && count > 0
          index = feedbin.hideQueue.indexOf(feedId)
          if index > -1
            feedbin.hideQueue.splice(index, 1);
          container.removeClass('zero-count')
      else
        container.removeClass('zero-count')
        if count == 0 && !_.contains(feedbin.hideQueue, feedId)
          container.addClass('zero-count')

  feedbin.updateTitle()
  feedbin.showFeedList()

class feedbin.CountsBehavior
  constructor: ->
    feedbin.applyCounts(false)
    $(document).on('feedbin:entriesLoaded', @applyState)
    $(document).on('click', '[data-behavior~=change_view_mode]', @changeViewMode)
    $(document).on('click', '[data-behavior~=show_entries]', @showEntries)
    $(document).on('ajax:beforeSend', '[data-behavior~=show_entry_content]', @showEntryContent)
    $(document).on('ajax:beforeSend', '[data-behavior~=toggle_read]', @toggleRead)
    $(document).on('ajax:beforeSend', '[data-behavior~=toggle_starred]', @toggleStarred)

  applyState: =>
    $('li[data-entry-id]').each (index, container) =>
      id = $(container).data('entry-id')
      if feedbin.specialCollection != 'updated' && @isRead(id)
        $(container).addClass('read')
      if @isStarred(id)
        $(container).addClass('starred')

  changeViewMode: (event) =>
    feedbin.hideQueue.length = 0
    element = $(event.currentTarget)
    $('[data-behavior~=change_view_mode]').removeClass('selected')
    element.addClass('selected')

    feedbin.data.viewMode = element.data('view-mode')

    $('body').removeClass('view_all view_unread view_starred');
    $('body').addClass(feedbin.data.viewMode);
    feedbin.applyCounts(false)

    if feedbin.openFirstItem
      $('[data-behavior~=feeds_target] li:visible').first().find('a')[0].click();
      feedbin.openFirstItem = false

  showEntryContent: (event, xhr) =>
    container = $(event.currentTarget)
    entry = $(container).data('entry-info')

    feedbin.previousEntry = feedbin.selectedEntry

    feedbin.selectedEntry =
      id: entry.id
      feed_id: entry.feed_id
      container: container

    if entry.id of feedbin.entries
      xhr.abort()
      feedbin.showEntry(entry.id)

    clearTimeout feedbin.recentlyReadTimer

    markedRead = false
    if !@isRead(entry.id)
      markedRead = true
      $.post($(container).data('mark-as-read-path')).fail((result)->
        if result.status == 422
          feedbin.refreshRetry(@)
      )
      feedbin.Counts.get().removeEntry(entry.id, entry.feed_id, 'unread')
      @mark('read')
      feedbin.recentlyReadTimer = setTimeout ( ->
        $.post($(container).data('recently-read-path')).fail((result)->
          if result.status == 422
            feedbin.refreshRetry(@)
        )
      ), 10000

    if @isUpdated(entry.id)
      feedbin.Counts.get().removeEntry(entry.id, entry.feed_id, 'updated')
      @mark('read')
      if !markedRead
        $.post $(container).data('mark-as-read-path')

  isRead: (entryId) ->
    feedbin.Counts.get().isRead(entryId)

  isUpdated: (entryId) ->
    feedbin.Counts.get().isUpdated(entryId)

  isStarred: (entryId) ->
    feedbin.Counts.get().isStarred(entryId)

  toggleRead: (event, xhr) =>
    if @isRead(feedbin.selectedEntry.id)
      feedbin.Counts.get().addEntry(feedbin.selectedEntry.id, feedbin.selectedEntry.feed_id, 'unread')
      @unmark('read')
    else
      feedbin.Counts.get().removeEntry(feedbin.selectedEntry.id, feedbin.selectedEntry.feed_id, 'unread')
      @mark('read')

  mark: (property) ->
    feedbin.applyCounts(true)
    $("[data-entry-id=#{feedbin.selectedEntry.id}]").addClass(property)

  unmark: (property) ->
    feedbin.applyCounts(true)
    if feedbin.specialCollection == 'updated'
      $(".entry-column [data-entry-id=#{feedbin.selectedEntry.id}]").removeClass(property)
    else
      $("[data-entry-id=#{feedbin.selectedEntry.id}]").removeClass(property)

  toggleStarred: (event, xhr) =>
    if @isStarred(feedbin.selectedEntry.id)
      feedbin.Counts.get().removeEntry(feedbin.selectedEntry.id, feedbin.selectedEntry.feed_id, 'starred')
      @unmark('starred')
    else
      feedbin.Counts.get().addEntry(feedbin.selectedEntry.id, feedbin.selectedEntry.feed_id, 'starred')
      @mark('starred')

  showEntries: (event) =>
    feedbin.specialCollection = $(event.currentTarget).data('special-collection')

    # Drain hide queue if this isn't the same collection
    if feedbin.selectedFeed && feedbin.selectedFeed[0] != $(event.currentTarget)[0]
      $.each feedbin.hideQueue, (index, feed_id) ->
        if feed_id != undefined
          item = $("li[data-feed-id=#{feed_id}]", '.feeds')
          $(item).addClass('zero-count')
      feedbin.hideQueue.length = 0

    feedbin.selectedFeed = $(event.currentTarget)
    return
