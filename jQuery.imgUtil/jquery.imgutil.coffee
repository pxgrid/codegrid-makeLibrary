# encapsulate plugin
do ($=jQuery, window=window, document=document) ->

  ns = {}

  # ============================================================
  # calcNaturalWH

  do ->

    cache = {} # cache caliculation result

    # prepare holder to caliculation
    $holder = null

    $holderSetup = ->
      $.Deferred (defer) ->
        $ ->
          $holder = $('<div id="calcNaturalWH-tempholder"></div>').css
            position: 'absolute'
            left: '-9999px'
            top: '-9999px'
          $('body').append $holder
          defer.resolve()
      .promise()

    naturalWHDetectable = (img) ->
      if(
        (not img.naturalWidth?) or
        (img.naturalWidth is 0) or
        (not img.naturalHeight?) or
        (img.naturalHeight is 0)
      )
        false
      else
        true

    # try caliculation 10 times if failed.
    # I don't know why but this caliculation fails sometimes.
    # delaying caliculation works well against this
    tryCalc = ($img, src) ->

      $img = $img.clone() # to avoid test style applied here
      img = $img[0]

      defer = $.Deferred()

      res = {}

      # prepare elements
      $img.css(width: 'auto', height: 'auto')
      $div = $('<div></div>').append($img)
      $holder.append $div

      count = 0
      oneTry = ->
        res.width = img.naturalWidth or $img.width()
        res.height = img.naturalHeight or $img.height()
        if(count > 10)
          $div.remove()
          defer.reject()
        else
          if (!res.width or !res.height)
            count++
            (wait 100).done -> oneTry()
          else
            cache[src]
            $div.remove()
            defer.resolve res

      oneTry()

      return defer.promise()

    # main
    ns.calcNaturalWH = $.ImgLoaderNs.createCachedFunction (defer, src) ->
      ($.loadImgWoCache src).then ($img) ->
        img = $img[0]
        if not (naturalWHDetectable img)
          $holderSetup().done ->
            (tryCalc $img, src).then (wh) ->
              defer.resolve wh, $img
            , ->
              defer.reject()
        else
          wh =
            width: img.naturalWidth
            height: img.naturalHeight
          cache[src] = wh
          defer.resolve wh, $img
      , ->
        defer.reject()

  # ============================================================
  # calcStylesToBeContainedInRect

  ns.calcStylesToBeContainedInRect = do ->

    defaults =
      imgWidth: null
      imgHeight: null
      rectWidth: null
      rectHeight: null

    return (options) ->

      o = $.extend {}, defaults, options
      ret = {}

      if o.imgWidth < o.rectWidth
        ret.left = Math.floor ((o.rectWidth - o.imgWidth) / 2)
      else
        ret.left = 0
      if o.imgHeight < o.rectHeight
        ret.top = Math.floor ((o.rectHeight - o.imgHeight) / 2)
      else
        ret.top = 0
      
      return ret

  # ============================================================
  # calcRectContainImgWH

  ns.calcRectContainImgWH = do ->

    # utils
    
    enlargeImgWH = (options) ->
      options.imgWidth = options.imgWidth * 100
      options.imgHeight = options.imgHeight * 100
      return options

    # options

    defaults =
      imgWidth: null
      imgHeight: null
      rectWidth: null
      rectHeight: null
      enlargeSmallImg: true

    # main

    return (options) ->

      o = $.extend {}, defaults, options

      if o.enlargeSmallImg
        o = enlargeImgWH o

      if (o.imgWidth < o.rectWidth) and (o.imgHeight < o.rectHeight)
        return {
          width: o.imgWidth
          height: o.imgHeight
        }

      shrinkRateW = o.rectWidth / o.imgWidth
      shrinkRateH = o.rectHeight / o.imgHeight

      if shrinkRateW < shrinkRateH
        return {
          width: o.rectWidth
          height: Math.ceil(o.imgHeight * shrinkRateW)
        }

      if shrinkRateW > shrinkRateH
        return {
          width: Math.ceil(o.imgWidth * shrinkRateH)
          height: o.rectHeight
        }

      if shrinkRateW is shrinkRateH
        return {
          width: o.imgWidth * shrinkRateW
          height: o.imgHeight * shrinkRateH
        }
    

  # ============================================================
  # calcStylesToCoverRect

  ns.calcStylesToCoverRect = do ->

    defaults =
      imgWidth: null
      imgHeight: null
      rectWidth: null
      rectHeight: null

    return (options) ->

      o = $.extend {}, defaults, options
      ret = {}
      
      if o.imgWidth > o.rectWidth
        ret.left = -1 * (Math.floor ((o.imgWidth - o.rectWidth) / 2))
      else
        ret.left = 0
      if o.imgHeight > o.rectHeight
        ret.top = -1 * (Math.floor ((o.imgHeight - o.rectHeight) / 2))
      else
        ret.top = 0

      return ret

  # ============================================================
  # calcRectCoverImgWH

  ns.calcRectCoverImgWH = do ->

    defaults =
      imgWidth: null
      imgHeight: null
      rectWidth: null
      rectHeight: null

    return (options) ->

      o = $.extend {}, defaults, options

      tryToFitW = ->
        shrinkRatio = o.rectWidth / o.imgWidth
        adjustedH = Math.floor (shrinkRatio * o.imgHeight)
        if adjustedH < o.rectHeight
          return false
        return {
          width: o.rectWidth
          height: adjustedH
        }
        
      tryToFitH = ->
        shrinkRatio = o.rectHeight / o.imgHeight
        adjustedW = Math.floor (shrinkRatio * o.imgWidth)
        if adjustedW < o.rectWidth
          return false
        return {
          width: adjustedW
          height: o.rectHeight
        }

      res = tryToFitW()
      if res is false
        res = tryToFitH()
        if res is false
          res.width = o.rectWidth
          res.height = o.rectHeight

      return res

  # ============================================================
  # AbstractImgRectFitter

  class ns.AbstractImgRectFitter

    constructor: ->

      src = @$el.attr @options.attr_src
      if src
        @options.src = src

      if @options.oninit
        data =
          el: @$el
        @options.oninit data

      @_doFirstRefresh()
    
    _doFirstRefresh: ->

      @_stillLoadingImg = true
      @_calcNaturalImgWH().done =>
        @_stillLoadingImg = false
        @refresh()

      return this

    _calcNaturalImgWH: ->

      defer = $.Deferred()

      success = (origWH, $img) =>
        @originalImgWidth = origWH.width
        @originalImgHeight = origWH.height
        if @options.cloneImg
          $img = $img.clone()
        @$img = $img
        defer.resolve()
        return

      fail = =>
        if @options.onfail
          @options.onfail()
        defer.reject()
        return

      ns.calcNaturalWH(@options.src).then success, fail

      return defer.promise()

    _putImg: ($img) ->

      if @options.overrideImgPut
        @options.overrideImgPut(@$el, $img)
      else
        @$el.empty().append $img
      return this

    _finalizeImg: (styles) ->

      if @options.useNewImgElOnRefresh
        $img = @$img.clone()
        $img.css styles
        @_putImg $img
      else
        @$img.css styles
        $imgInside = @$el.find 'img'
        if $imgInside.length is 0
          @_putImg @$img

      return this
      


  # ============================================================
  # ImgCoverRect
  
  class ns.ImgCoverRect extends ns.AbstractImgRectFitter

    @defaults =
      src: null
      oninit: null
      onfail: null
      cloneImg: true
      useNewImgElOnRefresh: false
      attr_src: 'data-imgcoverrect-src'
      overrideImgPut: null

    constructor: (@$el, options) ->

      @options = $.extend {}, ns.ImgCoverRect.defaults, options
      super

    refresh: ->

      return if @_stillLoadingImg is true

      @rectWidth = @$el.width()
      @rectHeight = @$el.height()

      adjustedWH = ns.calcRectCoverImgWH
        imgWidth: @originalImgWidth
        imgHeight: @originalImgHeight
        rectWidth: @rectWidth
        rectHeight: @rectHeight

      styles =
        width: adjustedWH.width
        height: adjustedWH.height

      otherStyles = ns.calcStylesToCoverRect
        imgWidth: adjustedWH.width
        imgHeight: adjustedWH.height
        rectWidth: @rectWidth
        rectHeight: @rectHeight

      styles = $.extend styles, otherStyles
      @_finalizeImg styles

      return this

  # bridge

  do ->

    dataKey = 'imgcoverrect'

    $.fn.imgCoverRect = (options) ->
      return @each (i, el) ->
        $el = $(el)
        $el.data dataKey, (new ns.ImgCoverRect $el, options)

    $.fn.refreshImgCoverRect = ->
      return @each (i, el) ->
        $el = $(el)
        instance = $el.data dataKey
        return unless instance
        instance.refresh()
    

  # ============================================================
  # imgContainRect

  class ns.ImgContainRect extends ns.AbstractImgRectFitter
    
    @defaults =
      src: null
      oninit: null
      onfail: null
      cloneImg: true
      enlargeSmallImg: true
      useNewImgElOnRefresh: false
      attr_src: 'data-imgcontainrect-src'
      overrideImgPut: null

    constructor: (@$el, options) ->

      @options = $.extend {}, ns.ImgContainRect.defaults, options
      super

    refresh: ->

      return if @_stillLoadingImg is true

      @rectWidth = @$el.width()
      @rectHeight = @$el.height()

      adjustedWH = ns.calcRectContainImgWH
        imgWidth: @originalImgWidth
        imgHeight: @originalImgHeight
        rectWidth: @rectWidth
        rectHeight: @rectHeight

      styles =
        width: adjustedWH.width
        height: adjustedWH.height

      otherStyles = ns.calcStylesToBeContainedInRect
        imgWidth: adjustedWH.width
        imgHeight: adjustedWH.height
        rectWidth: @rectWidth
        rectHeight: @rectHeight

      styles = $.extend styles, otherStyles
      @_finalizeImg styles

      return this
    
  # bridge
  
  do ->

    dataKey = 'imgcontainrect'

    $.fn.imgContainRect = (options) ->
      return @each (i, el) ->
        $el = $(el)
        $el.data dataKey, (new ns.ImgContainRect $el, options)

    $.fn.refreshImgContainRect = ->
      return @each (i, el) ->
        $el = $(el)
        instance = $el.data dataKey
        return unless instance
        instance.refresh()

  # ============================================================
  # globalify

  $.imgUtil = ns
