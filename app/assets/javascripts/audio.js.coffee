window.feedbin ?= {}

$.extend feedbin,

  initPlayer: (play = true) ->
    $('body').removeClass('audio-panel-minimized')
    $('body').removeClass('audio-panel-maximized')
    size = feedbin.data.audio_panel_size || "minimized"
    $('body').addClass("audio-panel-#{size}")

    window.player = new MediaElementPlayer 'audio_player',
      features: ['progress']
      classPrefix: 'mejs_empty__'
      defaultAudioWidth: 'auto'
      defaultAudioHeight: '5px'
      success: (mediaElement, domObject) ->
        data = $(domObject).data()
        if (data.entryId of feedbin.data.progress)
          progress = feedbin.data.progress[data.entryId]
          mediaElement.setCurrentTime(progress.progress)
        mediaElement.addEventListener 'timeupdate', _.throttle(feedbin.updateProgress, 5000, {leading: false})
        mediaElement.addEventListener 'playing', feedbin.playState
        mediaElement.addEventListener 'pause', feedbin.playState
        mediaElement.addEventListener 'seeked', _.throttle(feedbin.updateProgress, 1000, {leading: false})
        if play
          mediaElement.play()

  updateProgress: ->
    data = $(window.player.domNode).data()
    form = $("[data-behavior~=audio_target] [data-behavior~=audio_progress_form_#{data.entryId}]")
    feedbin.data.progress[data.entryId] =
      progress: window.player.currentTime
      duration: window.player.duration
    if form.length > 0
      field = form.find('#recently_played_entry_progress').val(window.player.currentTime)
      field = form.find('#recently_played_entry_duration').val(window.player.duration)
      form.submit()

  togglePlay: ->
    if window.player.paused
      window.player.play()
    else
      window.player.pause()

  setDuration: (entryId, duration) ->
    durationElement = $("[data-behavior~=audio_duration_#{entryId}]")
    if $.trim(durationElement.text()) == ''
      minutes = Math.floor(duration / 60);
      durationElement.html("#{minutes} minutes")

  playTime: (entryId) ->
    if (entryId of feedbin.data.progress)
      progress = feedbin.data.progress[entryId]
      feedbin.setDuration(entryId, progress.duration)

  playState: ->
    if typeof(window.player) != "undefined"
      data = $(window.player.domNode).data()
      duration = window.player.duration
      if !isNaN(duration)
        feedbin.setDuration(data.entryId, duration)

      play = $("[data-behavior~=audio_play_#{data.entryId}]")
      if window.player.paused
        play.addClass('paused')
        play.removeClass('playing')
      else
        play.addClass('playing')
        play.removeClass('paused')

  audioJump: (time) ->
    window.player.setCurrentTime(window.player.currentTime + time)


$.extend feedbin,

  audioInit:

    launch: ->
      $(document).on 'click', '[data-behavior~=audio_launch_player]', (event) ->
        init = ->
          $('body').addClass("animate-panel")
          source = $("[data-behavior~=audio_markup]")
          target = $("[data-behavior~=audio_target]")
          target.html(source.html())

          $("[data-behavior~=audio_target] [data-behavior~=now_playing_form]").submit()
          feedbin.initPlayer()

        if typeof(window.player) == "undefined"
          init()
        else
          size = feedbin.data.audio_panel_size || "minimized"
          $('body').addClass("audio-panel-#{size}")
          data = $(window.player.domNode).data()
          if data.entryId == $(@).data('entry-id')
            feedbin.togglePlay()
          else
            init()

    togglePanel: ->
      $(document).on 'click', '[data-behavior~=toggle_audio_panel]', (event) ->
        console.log event
        if $(event.target).has('[data-behavior~=toggle_audio_panel]')
          console.log 'yest'
          if $('body').hasClass('audio-panel-minimized')
            $('body').removeClass('audio-panel-minimized')
            $('body').addClass('audio-panel-maximized')
            feedbin.data.audio_panel_size = "maximized"
          else
            $('body').removeClass('audio-panel-maximized')
            $('body').addClass('audio-panel-minimized')
            feedbin.data.audio_panel_size = "minimized"
          form = $("[data-behavior~=audio_target] [data-behavior~=audio_panel_size]")
          form.find('#audio_panel_size').val(feedbin.data.audio_panel_size)
          form.submit()
        else
          console.log 'no'


    skipForward: ->
      $(document).on 'click', '[data-behavior~=audio_skip_forward]', (event) ->
        feedbin.audioJump(30)
        event.stopPropagation()

    skipBackward: ->
      $(document).on 'click', '[data-behavior~=audio_skip_backward]', (event) ->
        feedbin.audioJump(-30)
        event.stopPropagation()


    playPause: ->
      $(document).on 'click', '[data-behavior~=audio_play]', (event) ->
        feedbin.togglePlay()
        event.stopPropagation()

    close: ->
      $(document).on 'click', '[data-behavior~=close_audio]', (event) ->
        $("[data-behavior~=audio_target] [data-behavior~=remove_now_playing]").submit()

        window.player.pause()
        $('body').removeClass('audio-panel-minimized')
        $('body').removeClass('audio-panel-maximized')
        event.stopPropagation()




jQuery ->
  $.each feedbin.audioInit, (i, item) ->
    item()
