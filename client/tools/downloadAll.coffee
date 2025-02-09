import {defineTool} from './defineTool'
import {currentBoard, currentPage, currentRoom, setPageId} from '../AppState'
import dom from '../lib/dom'
import JSZip from 'jszip-sync'
defineTool
  name: 'downloadallSVG'
  category: 'download'
  icon: 'download-svg-all'
  help: 'Download/export all pages as a zip full of SVG files'
  click: (e, download = true) ->
    pages=currentRoom.get()?.data()?.pages
    svgs=[]
    for pageId in pages
      setPageId pageId if pageId?
      ##await until currentPage.get().id==pageId
      await new Promise (done)->
        setTimeout(done, 200)
      board = currentBoard()
      grid = currentPage.get()?.grid
      ## Temporarily remove transform for export
      root = board.root # <g>
      oldTransform = root.getAttribute 'transform'
      root.removeAttribute 'transform'
      ## Choose elements to export
      elts = board.renderedChildren()
      ## Compute bounding box using SVG's getBBox() and getCTM()
      bbox = board.renderedBBox elts
      ## Temporarily make grid span entire drawing
      if grid?
        grid.update bbox
        elts.splice 0, 0, grid.grid
      ## Convert everything to SVG
      svg = (elt.outerHTML for elt in elts).join '\n'
      .replace /&nbsp;/g, '\u00a0' # SVG doesn't support &nbsp;
      .replace /\bdata-tex="([^"]*)"/g, (match, tex) ->
        ## HTML doesn't escape < in attribute values, but XML needs it
        ## (allowing only > to be unescaped)
        "data-tex=\"#{tex
        .replace /</g, '&lt;'
        .replace />/g, '&gt;'
        }\""
      ## Compress using SVG's self-closing tags
      .replace ///(<(\w+)\b[^<>]*)> </\2>///g, '$1/>'
      ## Remove selection-helping rect.bbox elements from text objects
      .replace ///<rect [^<>]* class="bbox" [^<>]*/>///g, ''
      ## Reset transform and grid
      root.setAttribute 'transform', oldTransform if oldTransform?
      grid?.update()
      ## Create SVG header
      fonts = ''
      if /<text/.test svg
        for styleSheet in document.styleSheets
          if /fonts/.test styleSheet.href
            for rule in styleSheet.rules
              fonts += (rule.cssText.replace /unicode-range:.*?;/g, '') + '\n'
        fonts += '''
          text { font-family: 'Roboto Slab', serif }
          tspan.code { font-family: 'Roboto Mono', monospace }
          tspan.emph { font-style: oblique }
          tspan.strong { font-weight: bold }
          tspan.strike { text-decoration: line-through }

        '''
      width = bbox.max.x - bbox.min.x
      height = bbox.max.y - bbox.min.y
      svg = """
        <?xml version="1.0" encoding="utf-8"?>
        <svg xmlns="#{dom.SVGNS}" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="#{bbox.min.x} #{bbox.min.y} #{width} #{height}" width="#{width}px" height="#{height}px">
        <style>
        .pen line { stroke-linecap: round }
        .pen polyline { stroke-linecap: round; stroke-linejoin: round; fill: none }
        .grid { stroke-width: 0.96; stroke: #c4e3f4 }
        #{fonts}</style>
        #{svg}
        </svg>
      """
      ## Inline images.  (Asynchronous String.replace based on
      ## https://github.com/dsblv/string-replace-async)
      fetches = []
      svg.replace ///<image\b([^<>]*)>///g, (match, attrs) ->
        href = ///href="(https?://[^"]*)"///.exec attrs # ignore data: URLs
        crossorigin = ///crossorigin="([^"]*)"///.exec attrs
        if href? and crossorigin?
          href = href[1]
          crossorigin = crossorigin[1]
          fetches.push [href,
            cache: 'force-cache'
            credentials:
              if crossorigin == 'use-credentials'
                'include'
              else
                'same-origin'
          ]
        else
          fetches.push undefined
      images =
        for args in fetches
          if args?
            try
              response = await fetch ...args
              if response.status == 200
                blob = await response.blob()
                await new Promise (done) ->
                  reader = new FileReader
                  reader.onloadend = -> done reader.result
                  reader.readAsDataURL blob
            catch e
              console.log "Failed to inline image #{args[0]}: #{e}"
      count = 0
      svg = svg.replace ///<image\b([^<>]*)>///g, (match, attrs) ->
        image = images[count++]
        match
        .replace ///crossorigin="([^"]*)"///, ''
        .replace ///href="([^"]*)"///, (href, url) ->
          "xlink:href=\"#{image ? url}\""
      svgs.push svg
      ## Download file
    if download
      download = document.getElementById 'download'
      zip=new JSZip()
      zipped = zip.sync(->
        i=1
        for s in svgs
          zip.file "page-"+i+".svg", s 
          i++
        data = null
        zip.generateAsync({type: "blob"}).then (content) ->
          data = content
          return
        data
      ) 
      download.href = URL.createObjectURL zipped, type: 'data:application/zip'
      download.download = "cocreate-#{currentRoom.get().id}.zip"
      download.click()
    svgs
