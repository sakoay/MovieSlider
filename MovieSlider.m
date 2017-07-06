%%  MOVIESLIDER   Embeddable panel for playback, scrolling, and contrast/color map adjustment of 3D movies.
% 
% This software depends on the GUI Layout Toolbox:
%   http://www.mathworks.com/matlabcentral/fileexchange/47982-gui-layout-toolbox
% Make sure to get the version appropriate for your version of Matlab (R2014b onwards vs. older).
%
% The class MovieSlider creates a panel (that can be embedded like any other uix object) that
% displays the current frame of the movie tensor provided by the user, which is assumed to be
% 3-dimensional where the first two dimensions comprise a frame and the third dimension indexes a
% particular frame in the movie. GUI and keyboard controls allow automatic playback/looping as well
% as live scrolling through frames. There is also a button to cycle through contrast settings, and
% an extended configuration panel where the user can fine-tune the playback speed, color map and
% mapping range.
%
% Example usage:
%   shape = normpdf(-2.5:0.05:2.5, 0, 1);
%   tensor = bsxfun(@times, bsxfun(@times, shape, shape'), reshape(shape,1,1,[]));
%   movie = MovieSlider(tensor);
%
% Example of additional graphics drawn per frame:
%   hMark = line('Parent', movie.axsMovie, 'XData', [], 'YData', [], 'LineWidth', 2, 'Color', [1 1 1], 'Marker', 'o', 'MarkerSize', 8);
%   time = ( 0:size(tensor,3) )'; values = [size(tensor,2)/2 + 40*sin(time/5), size(tensor,1)/2 + 40*cos(time/8)];
%   movie.addIllustrations(hMark, {'XData', 'YData'}, num2cell(values));
%
% Various member functions exists for programatic control of some features:
%   show(...)                     : Sets the currently displayed movie (can also be done at
%                                   construction time) 
%   setPlaybackFPS(playbackFPS)   : Set playback rate in frames per second
%   setTitle(string)              : Sets the current title, or removes it if an empty string is
%                                   provided; a cellstring can also be provided to show a different
%                                   title per frame
%   setFrame(index)               : Sets the current frame to the given index
%   setFocusReturn(fcnReturn)     : Sets the function to call upon an 'escape' keypress
% 
% Movies including illustrations can be converted to a standard output format (.avi, .mp4 etc.)
% using the function save().
%
% Author:  Sue Ann Koay (koay@princeton.edu)
% Acknowledgements: 
%   The GUI icons are creations of Olha Kozachenko (https://www.iconfinder.com/olgakozachenko) 
%   that were made public under the Creative Commons license.
%
classdef MovieSlider < uix.VBox
  
  %------- Constants
  properties (Constant)
    DEFAULT_FPS           = 30
    FRAME_STEP            = 10
    MIN_NUMBINS           = 20
    CONTRAST_BINNING      = 30
%     CONTRAST_RANGE        = 10.^(-7:-1)
%     CONTRAST_RANGE        = 5e-7 * (1:100:1e3).^2
%     CONTRAST_RANGE        = 6e-10 * (1:1e2:1e3).^3
    CONTRAST_RANGE        = 6e-9 * (1:10:100).^4

    DIALOG_POSITION       = [0.4 0.35 0.2 0.3]
    DIALOG_MONITOR        = MovieSlider.getMonitorBySize()

    SELECT_COLOR          = cat(3, 156, 230, 255)/255
    GUI_COLOR             = cat(3, 0.9400, 0.9400, 0.9400)
    GUI_FONT              = 11
    GUI_BTNSIZE           = 20
    GUI_BUTTON            = [100 30]
    GUI_BORDER            = 5
    
    RANGE_COLOR           = [255 251 222]/255
    RANGE_BORDER          = [255 217 0  ]/255
    CONFIGURABLES         = {'contrastIndex', 'pixelRange', 'playbackFPS', 'colors'}
    
    COLORMAPS             = { 'gray', 'parula', 'hot', 'cool'         ...
                            , 'jet', 'hsv'                            ...
                            , 'spring', 'summer', 'autumn', 'winter'  ...
                            , 'winter', 'bone', 'copper', 'pink'      ...
                            };

    CODE_PATH             = parsePath(mfilename('fullpath'))
    ICON_END              = MovieSlider.loadIcon('end.png')
    ICON_PAUSE            = MovieSlider.loadIcon('pause.png')
    ICON_PLAY             = MovieSlider.loadIcon('play.png')
    ICON_REFRESH_OFF      = MovieSlider.loadIcon('refresh.png', MovieSlider.GUI_COLOR)
    ICON_REFRESH_ON       = MovieSlider.loadIcon('refresh.png', MovieSlider.SELECT_COLOR)
    ICON_STOP             = MovieSlider.loadIcon('stop.png')
    ICON_BEGIN            = MovieSlider.loadIcon('begin.png')
    ICON_CONFIG           = MovieSlider.loadIcon('config.png')
    ICON_SEARCH           = MovieSlider.loadIcon('search.png')
  end
  
  %------- Private data
  properties (Access = protected)
    figParent
    figConfig
    cntControl
    
    txtDummy
    txtInfo
    btnConfig
    btnPlay
    btnRepeat
    btnBegin
    btnEnd
    sldFrame
    
    hZoom
    
    fcnReturn
    illusProperty         = {}
    illusValue            = {}
    
    lsnScroll
    tmrPlayback
    syncSiblings
  end
  
  %------- Public data
  properties (SetAccess = protected)
    movie
    totalFrames
    frameTitle            = {}

    pixelPDF              = [0 0]
    pixelCDF              = [0 1]
    pixelValue            = [0 1]
    pixelDomain           = [-inf inf]
    pixelRange            = [0 1]

    colors
    doRepeat              = false
    currentFrame          = 1
    contrastIndex         = 1
    playbackFPS           = MovieSlider.DEFAULT_FPS

    axsMovie
    imgMovie
    titleMovie            = gobjects(1)
    illustration          = gobjects(0)
  end
  properties
    overlay               = struct()
  end
  
  
  %________________________________________________________________________
  methods

    %----- Constructor
    function obj = MovieSlider(parent, varargin)
      
      %% Default arguments and parent class constructor
      if nargin < 1
        parent          = figure;
      elseif isnumeric(parent) || numel(parent) > 1 || ~ishghandle(parent)
        varargin        = [parent, varargin];
        parent          = figure;
      end
      obj@uix.VBox( 'Parent', parent );
      
      
      %% Movie frame display
      obj.axsMovie      = axes      ( 'Parent'                  , uicontainer('Parent', obj)                    ...
                                    , 'ActivePositionProperty'  , 'Position'                                    ...
                                    , 'Box'                     , 'on'                                          ...
                                    , 'Layer'                   , 'top'                                         ...
                                    , 'XTick'                   , []                                            ...
                                    , 'YTick'                   , []                                            ...
                                    );
      obj.imgMovie      = image     ( 'Parent'                  , obj.axsMovie                                  ...
                                    , 'CData'                   , []                                            ...
                                    , 'CDataMapping'            , 'scaled'                                      ...
                                    , 'UserData'                , obj.currentFrame                              ...
                                    );
      hold(obj.axsMovie, 'on');

      %% Movie info and controls
      obj.cntControl    = uix.HBox  ( 'Parent'                  , obj                                           ...
                                    );
      obj.txtDummy      = uicontrol ( 'Parent'                  , obj.cntControl                                ...
                                    , 'Style'                   , 'text'                                        ...
                                    );
      obj.txtInfo       = uicontrol ( 'Parent'                  , obj.cntControl                                ...
                                    , 'Style'                   , 'edit'                                        ...
                                    , 'Enable'                  , 'inactive'                                    ...
                                    , 'FontSize'                , MovieSlider.GUI_FONT - 3                      ...
                                    , 'Callback'                , @obj.editSetFrame                             ...
                                    , 'ButtonDownFcn'           , @obj.enableSetFrame                           ...
                                    , 'TooltipString'           , 'Set frame'                                   ...
                                    );
      obj.btnConfig     = uicontrol ( 'Parent'                  , obj.cntControl                                ...
                                    , 'Style'                   , 'pushbutton'                                  ...
                                    , 'CData'                   , MovieSlider.ICON_CONFIG                       ...
                                    , 'BackgroundColor'         , MovieSlider.GUI_COLOR                         ...
                                    , 'Callback'                , @obj.cycleContrast                            ...
                                    , 'ButtonDownFcn'           , @obj.configureDisplay                         ...
                                    , 'TooltipString'           , 'Cycle contrast / Configure (right-click)'    ...
                                    );
      obj.btnPlay       = uicontrol ( 'Parent'                  , obj.cntControl                                ...
                                    , 'Style'                   , 'pushbutton'                                  ...
                                    , 'CData'                   , MovieSlider.ICON_PLAY                         ...
                                    , 'BackgroundColor'         , MovieSlider.GUI_COLOR                         ...
                                    , 'Callback'                , @obj.togglePlayback                           ...
                                    , 'UserData'                , false                                         ...
                                    , 'TooltipString'           , sprintf('Play (%.4g FPS)', obj.playbackFPS)   ...
                                    );
      obj.btnRepeat     = uicontrol ( 'Parent'                  , obj.cntControl                                ...
                                    , 'Style'                   , 'togglebutton'                                ...
                                    , 'CData'                   , MovieSlider.ICON_REFRESH_OFF                  ...
                                    , 'BackgroundColor'         , MovieSlider.GUI_COLOR                         ...
                                    , 'Callback'                , @obj.setRepeat                                ...
                                    , 'Value'                   , obj.doRepeat                                  ...
                                    , 'TooltipString'           , 'Turn on repeat'                              ...
                                    );
      obj.btnBegin      = uicontrol ( 'Parent'                  , obj.cntControl                                ...
                                    , 'Style'                   , 'pushbutton'                                  ...
                                    , 'CData'                   , MovieSlider.ICON_BEGIN                        ...
                                    , 'BackgroundColor'         , MovieSlider.GUI_COLOR                         ...
                                    , 'Callback'                , {@obj.setFrame, 1}                            ...
                                    , 'TooltipString'           , 'First frame'                                 ...
                                    );
      obj.sldFrame      = uicontrol ( 'Parent'                  , obj.cntControl                                ...
                                    , 'Style'                   , 'slider'                                      ...
                                    , 'Min'                     , 1                                             ...
                                    , 'Max'                     , 1                                             ...
                                    , 'Value'                   , 1                                             ...
                                    , 'SliderStep'              , [1 1]                                         ...
                                    , 'Enable'                  , 'off'                                         ...
                                    );
      obj.btnEnd        = uicontrol ( 'Parent'                  , obj.cntControl                                ...
                                    , 'Style'                   , 'pushbutton'                                  ...
                                    , 'CData'                   , MovieSlider.ICON_END                          ...
                                    , 'BackgroundColor'         , MovieSlider.GUI_COLOR                         ...
                                    , 'TooltipString'           , 'Last frame'                                  ...
                                    );
                     
      %% Configure formatting and sizes
      axis( obj.axsMovie, 'image', 'ij');
      set ( obj.cntControl, 'Widths'  , [0 6 1 1 1 1 -1 1] * MovieSlider.GUI_BTNSIZE );
      set ( obj           , 'Heights' , [-1 MovieSlider.GUI_BTNSIZE]               );
        
      %% Listeners for frame scrolling
      obj.lsnScroll     = addlistener(obj.sldFrame, 'ContinuousValueChange', @obj.drawFrame);
      
      %% Callback for mouseover info display and keyboard commands
      obj.figParent     = findParent(parent, 'figure');
      movieSliders      = get(obj.figParent, 'UserData');
      if isempty(movieSliders)
        movieSliders    = obj;
      else
        movieSliders(end+1) = obj;
      end
      set ( obj.figParent                                                           ...
          , 'UserData'              , movieSliders                                  ...
          , 'WindowButtonDownFcn'   , @MovieSlider.startZooming                     ...
          , 'WindowButtonMotionFcn' , @MovieSlider.updatePixelInfo                  ...
          , 'WindowKeyPressFcn'     , @MovieSlider.keyboardControl                  ...
          );
      
      %% Playback timer
      obj.tmrPlayback   = timer ( 'TimerFcn'        , @obj.playMovie          ...
                                , 'ExecutionMode'   ,'fixedRate'              ...
                                , 'BusyMode'        ,'drop'                   ...
                                );

        
      %% Shortcut to load a given movie at construction time
      if ~isempty(varargin)
        obj.show(varargin{:});
      end
      
    end
    
    %----- Destructor
    function delete(obj)
      if ~isempty(obj.tmrPlayback)
        stop(obj.tmrPlayback);
        delete(obj.tmrPlayback);
      end
      delete@uix.VBox(obj);
    end
    
    %----- Retrieves the current configuration as can be passed to show()
    function config = configuration(obj)
      config  = {obj.colors, obj.pixelDomain, obj.pixelRange, obj.contrastIndex};
    end
    
    %----- Sets the currently displayed movie
    function show(obj, movie, colors, pixelDomain, contrast, contrastIndex)
      
      %% Default arguments 
      if nargin < 3 || isempty(colors)
        colors          = 'default';
      end
      if nargin < 4 || isempty(pixelDomain)
        if min(movie(:)) == 0
          pixelDomain   = [0, inf];
        else
          pixelDomain   = [-inf, inf];
        end
      end
      if nargin < 5 || isempty(contrast)
        contrast        = 1;
      end
      if nargin > 5     % overridden by contrast, but set anyway for continuity
        obj.contrastIndex = contrastIndex;
      end
      
      
      %% Movie properties
      obj.movie         = movie;
      obj.totalFrames   = size(obj.movie, ndims(obj.movie));
      
      %% Contrast determination only for 3D movies (as opposed to directly provided RGB)
      if ndims(obj.movie) == 3
        if obj.totalFrames >= MovieSlider.MIN_NUMBINS * MovieSlider.CONTRAST_BINNING
          binnedMovie   = rebin(obj.movie, MovieSlider.CONTRAST_BINNING, 3, @mean, 'omitnan');
      else
          binnedMovie   = obj.movie;
      end
      if islogical(contrast) && numel(contrast) == size(movie,1)*size(movie,2)
          imgMask       = frameMask(size(binnedMovie), contrast, 1);
          [obj.pixelPDF, edges] = histcounts(binnedMovie(imgMask), 'Normalization', 'prob');
        if nargin > 5
          contrast      = contrastIndex;
        else
          contrast      = 1;
        end
      else
          [obj.pixelPDF, edges] = histcounts(binnedMovie, 'Normalization', 'prob');
      end
      
      if numel(obj.pixelPDF) < 2
        obj.pixelPDF    = [0 1];
        obj.pixelValue  = [0 1];
      else
        obj.pixelValue  = (edges(1:end-1) + edges(2:end)) / 2;
      end
      obj.pixelCDF      = cumsum(obj.pixelPDF);
      obj.pixelDomain   = pixelDomain;
      
      obj.colors        = colors;
      obj.currentFrame  = 1;
      end
      
      %% Movie frame display
      set ( obj.axsMovie                                                              ...
          , 'XLim'                    , [0.5, 0.5+max(1,size(movie,2))]               ...
          , 'YLim'                    , [0.5, 0.5+max(1,size(movie,1))]               ...
          );
      if isempty(movie)
        set ( obj.imgMovie                                                            ...
            , 'CData'                 , 0                                             ...
            , 'UserData'              , obj.currentFrame                              ...
            );
      else
        if ndims(movie) == 3
          movieFrame      = movie(:,:,obj.currentFrame);
        else
          movieFrame      = movie(:,:,:,obj.currentFrame);
        end
        set ( obj.imgMovie                                                            ...
            , 'CData'                 , movieFrame                                    ...
            , 'UserData'              , obj.currentFrame                              ...
            );
      set ( obj.sldFrame                                                              ...
          , 'Min'                     , 1                                             ...
            , 'Max'                   , obj.totalFrames                               ...
            , 'SliderStep'            , min([1 MovieSlider.FRAME_STEP]/(obj.totalFrames - 1), 1)  ...
          , 'Value'                   , obj.currentFrame                              ...
          );
      set ( obj.btnEnd                                                                ...
            , 'Callback'              , {@obj.setFrame, obj.totalFrames}              ...
          );
      end

      if obj.totalFrames > 1
        set(obj.sldFrame, 'Enable', 'on');
      else
        set(obj.sldFrame, 'Enable', 'off');
      end
                     

      stop(obj.tmrPlayback);

      %% Apply formatting
      colormap( obj.axsMovie, colors );
      obj.setContrast(contrast);
      
    end
    
    %----- Sets the display region size for this MovieSlider
    function displayPos = setSize(obj, widthInPixels, heightInPixels)
      if nargin < 3 && numel(widthInPixels) == 2
        heightInPixels  = widthInPixels(1);
        widthInPixels   = widthInPixels(2);
      end
      
      %% Compute required size of figure to contain the desired display area size
      figSize         = get(obj.figParent, 'Position');
      figCorner       = figSize(1:2) + figSize(3:4);
      targetSize        = [widthInPixels + 2*MovieSlider.GUI_BTNSIZE, heightInPixels + 3*MovieSlider.GUI_BTNSIZE];
      targetPos       = [max(1, figCorner - targetSize), targetSize];
      
      %% Set the figure and axes positions
      displayPos      = [MovieSlider.GUI_BTNSIZE, MovieSlider.GUI_BTNSIZE, widthInPixels, heightInPixels];
      
      set(obj.figParent, 'Position', targetPos);
      set(obj.axsMovie, 'Units', 'pixels');
      set(obj.axsMovie, 'Position', displayPos);
      
      %% Restore normalized units so that the display area resizes with figure size
      displayPos      = get(obj.axsMovie, 'Position');
      set(obj.axsMovie, 'Units', 'normalized');
    end
    
    %----- Set playback rate
    function setPlaybackFPS(obj, playbackFPS)
      obj.playbackFPS = playbackFPS;
      set(obj.btnPlay, 'TooltipString', sprintf('Play (%.4g FPS)', obj.playbackFPS));
    end
    
    %----- Sets the current title, or removes it if an empty string is provided
    function setTitle(obj, string, varargin)
      if isempty(string)
        delete(obj.titleMovie);
        obj.titleMovie  = gobjects(1);
        obj.frameTitle  = {};
      elseif iscell(string)
        obj.titleMovie  = title(obj.axsMovie, string{obj.currentFrame}, varargin{:});
        obj.frameTitle  = string;
      else
        obj.titleMovie  = title(obj.axsMovie, string, varargin{:});
        obj.frameTitle  = {};
      end
    end

    %----- Sets per-frame updates for illustration objects
    %   Input:
    %     handle      : a graphics handle to set the properties of per frame
    %     properties  : a length p cell array of properties to set
    %     values      : an n-by-p cell array of property values, where n is the number of frames and
    %                   p the number of properties
    function addIllustrations(obj, handle, properties, values)
      
      for iIllus = 1:numel(handle)
        obj.illustration(end+1)   = handle;
        obj.illusProperty{end+1}  = properties;
        obj.illusValue{end+1}     = values(:,:,iIllus);
      end
      
      obj.drawFrame(obj.currentFrame, true);
      
    end
    
    %----- Sets the current frame to the given index
    function setFrame(obj, handle, event, index)
      if nargin < 3
        index = handle;
      end
      
      index   = max(1, min(index, obj.totalFrames));
      if index ~= obj.currentFrame
        set(obj.sldFrame, 'Value', index);
        obj.drawFrame(index);
      end
    end
    
    %----- Sets the function to call upon an 'escape' keypress
    function setFocusReturn(obj, fcnReturn)
      obj.fcnReturn = fcnReturn;
    end
    
    %----- Makes a clone of this MovieSlider in a new figure
    function clone(obj, handle, event)
      dup   = MovieSlider(figure, obj.movie, obj.colors, obj.pixelDomain, obj.contrastIndex);
      for prop = {'pixelPDF', 'pixelCDF', 'pixelValue', 'pixelRange'}
        dup.(prop{:}) = obj.(prop{:});
      end
      
      prop  = get(obj.title);
      dup.setTitle(obj.frameTitle, prop{:}, 'Parent', dup.axsMovie);
    end
    
    
    %----- Saves all frames of this MovieSlider into a video file; see VideoWriter for allowed formats
    function save(obj, outputFile, frameRate, varargin)
      %% Default arguments
      if nargin < 3
        frameRate         = [];
      end
      
      %% Optionally the user can provide a VideoWriter object with their desired configuration
      if isa(outputFile, 'VideoWriter')
        writer            = outputFile;
      else
        writer            = VideoWriter(outputFile, varargin{:});
      end
      
      if ~isempty(frameRate)
        writer.FrameRate  = frameRate;
      end
      
      %% Save current state 
      currentFrame        = obj.currentFrame;
      
      %% Iterate through frames and output into video file
      open(writer);
      for iFrame = 1:obj.totalFrames
        obj.setFrame(iFrame);
        frame             = getframe(obj.axsMovie);
        writeVideo(writer, frame);
      end
      close(writer);
      
      %% Restore current state
      obj.setFrame(currentFrame);
    end
    
  end
  

  %________________________________________________________________________
  methods (Access = protected)
    
    %----- Ensure that synchronized objects exist
    function checkSiblings(obj)
      obj.syncSiblings(~ishghandle(obj.syncSiblings)) = [];
    end
    
    
    %----- Shift the current frame by the given amount
    function shiftFrame(obj, shift)
      if shift < 0
        obj.setFrame(max(1, obj.currentFrame + shift));
      else
        obj.setFrame(min(obj.totalFrames, obj.currentFrame + shift));
      end
    end
    
    %----- Set contrast level
    function setContrast(obj, contrast)
      if ndims(obj.movie) > 3
        return;
      end
      
      if numel(contrast) == 1
        %% Select only values of CDF that are unique
        obj.contrastIndex   = max(1, min(contrast, numel(MovieSlider.CONTRAST_RANGE)));
        saturation          = MovieSlider.CONTRAST_RANGE(obj.contrastIndex);
        sel                 = [1, 1 + find(diff(obj.pixelCDF) ~= 0)];
        
        %% The following avoids creating very large ranges in the case of many empty bins in the PDF
        iValue              = interp1(obj.pixelCDF(sel), 1:numel(sel), [saturation, 1-saturation], 'linear', 'extrap');
        inRange             = iValue > 1 & iValue < numel(sel);
        iValue              = iValue(inRange);
        pdfLo               = obj.pixelValue(sel(floor(iValue)));
        pdfUp               = obj.pixelValue(sel(ceil(iValue)));
        
        %% Default to maximum range unless there is a valid solution above
        obj.pixelRange      = obj.pixelValue([1 end]);
        obj.pixelRange(inRange) = pdfLo + (pdfUp - pdfLo) .* (iValue - floor(iValue));
        
%         obj.pixelRange      = interp1(obj.pixelCDF(sel), obj.pixelValue(sel), [saturation, 1-saturation], 'linear', 'extrap');
        
        %% Domain-specific constraints (e.g. fix left edge at 0 for positive domain)
        sel                 = isfinite(obj.pixelDomain);
        obj.pixelRange(sel) = obj.pixelDomain(sel);
      elseif contrast(2) > contrast(1)
        obj.pixelRange      = contrast;
      else
        return;
      end
      
      set(obj.axsMovie, 'CLim', obj.pixelRange);
    end
    
    
    %----- Callback for user to enter the desired frame
    function editSetFrame(obj, handle, event, index)
      set(handle, 'Enable', 'inactive');
      uicontrol(obj.txtDummy);
      stop(obj.tmrPlayback);
      
      value   = sscanf(get(handle, 'String'), '%d');
      if isempty(value)
        value = obj.currentFrame;
      end
      obj.setFrame(value);
    end
    
    %----- Callback for user to enter the desired frame
    function enableSetFrame(obj, handle, event, index)
      set(handle, 'Enable', 'on', 'String', '');
      uicontrol(handle);
    end
    
    %----- Callback to set whether the movie replays when at the end
    function setRepeat(obj, handle, event)
      obj.doRepeat  = get(handle, 'Value');
      if obj.doRepeat
        set(handle, 'CData', MovieSlider.ICON_REFRESH_ON , 'TooltipString', 'Turn off repeat');
      else
        set(handle, 'CData', MovieSlider.ICON_REFRESH_OFF, 'TooltipString', 'Turn on repeat');
      end
      
      obj.checkSiblings();
      for iSib = 1:numel(obj.syncSiblings)
        other           = obj.syncSiblings(iSib);
        other.doRepeat  = obj.doRepeat;
        if other.doRepeat
          set(other.btnRepeat, 'CData', MovieSlider.ICON_REFRESH_ON);
        else
          set(other.btnRepeat, 'CData', MovieSlider.ICON_REFRESH_OFF);
        end
      end
    end
    
    %----- Helper for drawFrame() that only affects this object
    function doDrawFrame(obj, iFrame)
      %% Set movie frame image
      if ndims(obj.movie) == 3
      set(obj.imgMovie, 'CData', obj.movie(:,:,iFrame), 'UserData', iFrame);
      else
        set(obj.imgMovie, 'CData', obj.movie(:,:,:,iFrame), 'UserData', iFrame);
      end
      
      obj.currentFrame      = iFrame;
      set(obj.txtInfo, 'String', sprintf('%d/%d', iFrame, obj.totalFrames));

      %% Update title per frame
      if ~isempty(obj.frameTitle)
        set(obj.titleMovie, 'String', obj.frameTitle{iFrame});
      end

      %% Update illustration objects per frame
      for iIllus = 1:numel(obj.illustration)
        prop    = [ obj.illusProperty{iIllus}           ...
                  ; obj.illusValue{iIllus}(iFrame,:)    ...
                  ];
        set( obj.illustration(iIllus), prop{:} );
      end
    end
    
    %----- Callback for scrolling between frames
    function drawFrame(obj, handle, event, doForce)
      
      % Frame to set the currently displayed one to
      if isnumeric(handle)
        iFrame    = handle;
      else
        iFrame    = min(obj.totalFrames, max(1, round(get(handle, 'Value'))));
      end
      if nargin > 2 && islogical(event)
        doForce   = event;
      elseif nargin < 4
        doForce   = false;
      end
      
      % Update frame only if different from previous
      if doForce || iFrame ~= obj.currentFrame
        obj.doDrawFrame(iFrame);
      end
      
      % Scroll to the same frame for all associated MovieSlider siblings
      obj.checkSiblings();
      for iSib = 1:numel(obj.syncSiblings)
        other     = obj.syncSiblings(iSib);
        jFrame    = min(other.totalFrames, max(1, iFrame));
        if doForce || jFrame ~= other.currentFrame
          other.doDrawFrame(jFrame);
        end
      end
    
      % Set input focus and refresh graphics
      set(obj.figParent, 'CurrentAxes', obj.axsMovie);
      drawnow;
      
    end
    
    %----- Callback to load the next frame in playback mode
    function playMovie(obj, handle, event)
      if obj.currentFrame >= obj.totalFrames
        if obj.doRepeat
          obj.currentFrame  = 0;
        else
          obj.togglePlayback(obj.btnPlay, [], true);
          return;
        end
      end
      obj.setFrame(obj.currentFrame + 1);
    end
    
    %----- Callback to start/stop automatic playback
    function togglePlayback(obj, handle, event, forceStop)
      if nargin < 4
        forceStop   = false;
      end
      stop(obj.tmrPlayback);
      
      % If already playing, stop
      if forceStop || get(handle, 'UserData')
        set(handle, 'CData', MovieSlider.ICON_PLAY, 'UserData', false, 'TooltipString', sprintf('Play (%.4g FPS)', obj.playbackFPS));
        
      % If not playing, start
      else
        if obj.currentFrame >= obj.totalFrames
          obj.currentFrame  = 0;
        end
        
        set(handle, 'CData', MovieSlider.ICON_STOP, 'UserData', true, 'TooltipString', 'Stop');
        set(obj.tmrPlayback, 'Period', max(1,round(1000/obj.playbackFPS))/1000);
        start(obj.tmrPlayback);
      end
    end
    
    %----- Callback for cycling contrast levels
    function cycleContrast(obj, handle, event)
      obj.setContrast(1 + mod(obj.contrastIndex, numel(MovieSlider.CONTRAST_RANGE)));
    end
    
    %----- Callback for adjusting frame display parameters
    function configureDisplay(obj, handle, event)
      
      % Allow only one instance
      if ishghandle(obj.figConfig)
        figure(obj.figConfig);
        return;
      end
      
      
      % Store current configuration in case of user cancel
      original        = struct();
      for field = MovieSlider.CONFIGURABLES
        original.(field{:}) = obj.(field{:});
      end
      
      
      % Create dialog box
      obj.figConfig   = makePositionedFigure( MovieSlider.DIALOG_POSITION                               ...
                                            , MovieSlider.DIALOG_MONITOR                                ...
                                            , 'OuterPosition'                                           ...
                                            , 'Name'                  , 'Movie Slider Configuration'    ...
                                            , 'ToolBar'               , 'none'                          ...
                                            , 'MenuBar'               , 'none'                          ...
                                            , 'NumberTitle'           , 'off'                           ...
                                            , 'CloseRequestFcn'       , @restoreConfig                  ...
                                            , 'WindowButtonMotionFcn' , @mouseHoverHint                 ...
                                            , 'WindowButtonUpFcn'     , @(h,e) set(h,'WindowButtonMotionFcn',@mouseHoverHint)  ...
                                            , 'Visible'               , 'off'                           ...
                                            );

      % Configuration panels
      cntConfig       = uix.HBox('Parent', obj.figConfig, 'Padding', MovieSlider.GUI_BORDER);
      cntContrast     = uix.VBox('Parent', cntConfig);
                        uix.Empty('Parent', cntConfig);
      cntControls     = uix.VBox('Parent', cntConfig, 'Padding', MovieSlider.GUI_BORDER, 'Spacing', MovieSlider.GUI_BORDER);

      % Contrast adjustment
      leeway          = 0.05 * (obj.pixelValue(end) - obj.pixelValue(1));
      axsRange        = obj.pixelValue([1 end]) + [-1 1]*leeway;
      axsPDF          = axes      ( 'Parent'          , cntContrast                               ...
                                  , 'Box'             , 'on'                                      ...
                                  , 'Layer'           , 'top'                                     ...
                                  , 'XLim'            , axsRange                                  ...
                                  , 'FontSize'        , MovieSlider.GUI_FONT - 1                  ...
                                  , 'Units'           , 'pixels'                                  ...
                                  );
      sldContrast     = uicontrol ( 'Parent'          , cntContrast                               ...
                                  , 'Style'           , 'slider'                                  ...
                                  , 'Min'             , 1                                         ...
                                  , 'Max'             , numel(MovieSlider.CONTRAST_RANGE)         ...
                                  , 'SliderStep'      , [1 5]/(numel(MovieSlider.CONTRAST_RANGE)-1) ...
                                  , 'Value'           , obj.contrastIndex                         ...
                                  , 'Callback'        , @slideContrast                            ...
                                  , 'TooltipString'   , 'Preset contrast levels'                  ...
                                  );
      cntManual       = uix.HBox( 'Parent', cntContrast, 'Padding', MovieSlider.GUI_BORDER );
      editBound(1)    = uicontrol ( 'Parent'          , cntManual                                 ...
                                  , 'Style'           , 'edit'                                    ...
                                  , 'String'          , sprintf('%.4g', obj.pixelRange(1))        ...
                                  , 'FontSize'        , MovieSlider.GUI_FONT                      ...
                                  , 'Callback'        , {@editContrast, 1}                        ...
                                  , 'TooltipString'   , 'Color range minimum'                     ...
                                  );
                        uix.Empty ( 'Parent', cntManual );
      editBound(2)    = uicontrol ( 'Parent'          , cntManual                                 ...
                                  , 'Style'           , 'edit'                                    ...
                                  , 'String'          , sprintf('%.4g', obj.pixelRange(end))      ...
                                  , 'FontSize'        , MovieSlider.GUI_FONT                      ...
                                  , 'Callback'        , {@editContrast, 2}                        ...
                                  , 'TooltipString'   , 'Color range maximum'                     ...
                                  );
      
      % Other controls
      txtFPS          = uicontrol ( 'Parent'          , cntControls                               ...
                                  , 'Style'           , 'text'                                    ...
                                  , 'String'          , 'Frames/sec:'                             ...
                                  , 'FontSize'        , MovieSlider.GUI_FONT                      ...
                                  );
      edtFPS          = uicontrol ( 'Parent'          , cntControls                               ...
                                  , 'Style'           , 'edit'                                    ...
                                  , 'String'          , sprintf('%.4g', obj.playbackFPS)          ...
                                  , 'FontSize'        , MovieSlider.GUI_FONT                      ...
                                  );
      edtColors       = uicontrol ( 'Parent'          , cntControls                               ...
                                  , 'Style'           , 'edit'                                    ...
                                  , 'String'          , obj.colors                                ...
                                  , 'FontSize'        , MovieSlider.GUI_FONT                      ...
                                  , 'Callback'        , @setColors                                ...
                                  , 'TooltipString'   , 'Custom colormap'                         ...
                                  );
      mnuColors       = uicontrol ( 'Parent'          , cntControls                               ...
                                  , 'Style'           , 'listbox'                                 ...
                                  , 'String'          , MovieSlider.COLORMAPS                     ...
                                  , 'FontSize'        , MovieSlider.GUI_FONT                      ...
                                  , 'Callback'        , {@setColors, edtColors}                   ...
                                  , 'Min'             , 0                                         ...
                                  , 'Max'             , 2                                         ...
                                  , 'Value'           , find(strcmp(MovieSlider.COLORMAPS, obj.colors)) ...
                                  );
                        uix.Empty ( 'Parent', cntControls );
      
      % Dialog box ok/cancel
      btnOK           = uicontrol ( 'Parent'          , cntControls                               ...
                                  , 'Style'           , 'pushbutton'                              ...
                                  , 'String'          , 'OK'                                      ...
                                  , 'FontSize'        , MovieSlider.GUI_FONT                      ...
                                  , 'Callback'        , @acceptConfig                             ...
                                  , 'TooltipString'   , 'Apply configuration'                     ...
                                  );
      btnCancel       = uicontrol ( 'Parent'          , cntControls                               ...
                                  , 'Style'           , 'pushbutton'                              ...
                                  , 'String'          , 'Cancel'                                  ...
                                  , 'FontSize'        , MovieSlider.GUI_FONT                      ...
                                  , 'Callback'        , @restoreConfig                            ...
                                  , 'TooltipString'   , 'Discard configuration'                   ...
                                  );
      btnClone        = uicontrol ( 'Parent'          , cntControls                               ...
                                  , 'Style'           , 'pushbutton'                              ...
                                  , 'String'          , 'Clone'                                   ...
                                  , 'FontSize'        , MovieSlider.GUI_FONT                      ...
                                  , 'Callback'        , @cloneSelf                                ...
                                  , 'TooltipString'   , sprintf('Clone MovieSlider into new figure\n(discards changes to configuration!)') ...
                                  );

      % Size of various panels
      set ( cntConfig                                                                             ...
          , 'Widths'          , [-1, MovieSlider.GUI_BTNSIZE, MovieSlider.GUI_BUTTON(1) + 2*MovieSlider.GUI_BORDER]   ...
          );
      set ( cntContrast                                                                           ...
          , 'Heights'         , [-1, MovieSlider.GUI_BTNSIZE, MovieSlider.GUI_BUTTON(2)+MovieSlider.GUI_BORDER]       ...
          );
      set ( cntManual                                                                             ...
          , 'Widths'          , [MovieSlider.GUI_BUTTON(1), -1, MovieSlider.GUI_BUTTON(1)]        ...
          );
      set ( cntControls                                                                           ...
          , 'Heights'         , [0.5 1 1 -1 1 1 1 1]*MovieSlider.GUI_BUTTON(2)                    ...
          );
        
      % Plot pixel distribution and range
      hPDF            = line  ( 'Parent'        , axsPDF                      ...
                              , 'XData'         , obj.pixelValue              ...
                              , 'YData'         , obj.pixelPDF                ...
                              , 'LineWidth'     , 1                           ...
                              , 'Color'         , [0 0 0]                     ...
                              , 'PickableParts' , 'none'                      ...
                              );
      xlabel(axsPDF, 'Pixel value', 'FontSize', MovieSlider.GUI_FONT-1);
      ylabel(axsPDF, 'Frequency'  , 'FontSize', MovieSlider.GUI_FONT-1);

      yRange          = get(axsPDF, 'YLim');
      yRange(1)       = 0;
      [rngX, rngY]    = rectangleCorners(obj.pixelRange(1), 0, obj.pixelRange(end)-obj.pixelRange(1), yRange(end));
      hRange          = patch ( 'Parent'        , axsPDF                      ...
                              , 'XData'         , rngX                        ...
                              , 'YData'         , rngY                        ...
                              , 'EdgeColor'     , 'none'                      ...
                              , 'FaceColor'     , MovieSlider.RANGE_COLOR     ...
                              , 'PickableParts' , 'none'                      ...
                              );
      hBound(1)       = line  ( 'Parent'        , axsPDF                      ...
                              , 'XData'         , [1 1]*obj.pixelRange(1)     ...
                              , 'YData'         , yRange                      ...
                              , 'LineWidth'     , 2                           ...
                              , 'Color'         , MovieSlider.RANGE_BORDER    ...
                              , 'ButtonDownFcn' , {@startDragBound, 1}        ...
                              );
      hBound(2)       = line  ( 'Parent'        , axsPDF                      ...
                              , 'XData'         , [1 1]*obj.pixelRange(end)   ...
                              , 'YData'         , yRange                      ...
                              , 'LineWidth'     , 2                           ...
                              , 'Color'         , MovieSlider.RANGE_BORDER    ...
                              , 'ButtonDownFcn' , {@startDragBound, 2}        ...
                              );
      uistack(hBound, 'bottom');
      uistack(hRange, 'bottom');
      set(obj.figConfig, 'Visible', 'on');
      
      
      % Callbacks for GUI interaction
      function redrawRange(index)
        if ~ishghandle(obj.figConfig)
          return;
        end
        if nargin < 1
          index           = 1:numel(hBound);
        end
        
        [rngX, rngY]      = rectangleCorners(obj.pixelRange(1), 0, obj.pixelRange(end)-obj.pixelRange(1), yRange(end));
        set(hRange, 'XData', rngX, 'YData', rngY);
        for iBound = index
          set(hBound(iBound), 'XData', [1 1]*obj.pixelRange(iBound));
        end
      end
      
      function setColors(handle, event, hEdit)
        if ~ishghandle(obj.figConfig)
          return;
        end
        
        value         = get(handle, 'String');
        if nargin > 2
          indices     = get(handle, 'Value');
          if isempty(indices)
            return;
          end
          value       = value{indices(1)};
          set(hEdit, 'String', value);
        end
        
        obj.colors    = value;
        colormap(obj.axsMovie, value);
      end
      
      function slideContrast(handle, event)
        if ~ishghandle(obj.figConfig)
          return;
        end
        
        obj.setContrast(round(get(handle, 'Value')));
        set(editBound(1), 'String', sprintf('%.4g', obj.pixelRange(1)));
        set(editBound(2), 'String', sprintf('%.4g', obj.pixelRange(end)));
        redrawRange();
        drawnow;
      end
      
      function editContrast(handle, event, index)
        if ~ishghandle(obj.figConfig)
          return;
        end
        
        obj.pixelRange(index) = str2double(get(handle, 'String'));
        obj.setContrast(obj.pixelRange);
        redrawRange(index);
        drawnow;
      end
      
      beingCalled     = [];
      function dragBound(handle, event, index)
        if isempty(beingCalled)
          beingCalled = true;
        else
          return;
        end
        
        if ~ishghandle(obj.figConfig)
          return;
        end
        
        mousePos      = get(axsPDF, 'CurrentPoint');
        range         = obj.pixelRange;
        range(index)  = mousePos(1);
        if range(2) > range(1)
          set(editBound(index), 'String', sprintf('%.4g', range(index)));
          editContrast(editBound(index), event, index);
        end
        
        beingCalled   = [];
      end
      
      function startDragBound(handle, event, index)
        if ~ishghandle(obj.figConfig)
          return;
        end
        
        set(obj.figConfig, 'WindowButtonMotionFcn', {@dragBound, index});
      end
      
      function mouseHoverHint(handle, event)
        if ~ishghandle(obj.figConfig)
          return;
        end
        
        mousePos      = get(axsPDF, 'CurrentPoint');
        axsPos        = get(axsPDF, 'Position');
        dPix          = axsPos(3) * abs(mousePos(1) - obj.pixelRange ) / (axsRange(end) - axsRange(1));

        if any(dPix < 2)
          set(handle, 'Pointer', 'left');
        else
          set(handle, 'Pointer', 'arrow');
        end
      end
      
      function acceptConfig(handle, event)
        obj.contrastIndex = get(sldContrast, 'Value');
        obj.pixelRange    = [ str2double(get(editBound(1), 'String'))            ...
                            , str2double(get(editBound(2), 'String'))            ...
                            ];
        obj.setPlaybackFPS(str2double(get(edtFPS, 'String')));
        if ishghandle(obj.figConfig)
          delete(obj.figConfig);
        end
        obj.figConfig     = [];
      end
      
      function restoreConfig(handle, event)
        for field = MovieSlider.CONFIGURABLES
          obj.(field{:})  = original.(field{:});
        end
        obj.setContrast(obj.pixelRange);
        colormap(obj.axsMovie, obj.colors);
        drawnow;

        if ishghandle(obj.figConfig)
          delete(obj.figConfig);
        end
        obj.figConfig     = [];
      end
      
      function cloneSelf(handle, event)
        restoreConfig();
        obj.clone();
      end
                          
    end
    
  end
  
  
  %________________________________________________________________________
  methods (Static)

    %----- Synchronize frame display of all given movie sliders
    function synchronizeFrames(sliders, doSync)
      if nargin < 2 || doSync
        for iMov = 1:numel(sliders)
          sliders(iMov).syncSiblings  = sliders([1:iMov-1, iMov+1:end]);
        end
      else
        for iMov = 1:numel(sliders)
          sliders(iMov).syncSiblings  = [];
        end
      end
    end
    
    
    %----- Load GUI icon
    function icon = loadIcon(iconFile, background)
      if nargin < 2
        background  = MovieSlider.GUI_COLOR;
      end
      
      [~, ~, alpha] = imread(fullfile(MovieSlider.CODE_PATH, iconFile));
      alpha         = imresize(double(alpha), [1 1] * MovieSlider.GUI_BTNSIZE, 'lanczos3');
      alpha         = alpha .* (alpha > 0) / max(alpha(:));
      icon          = bsxfun(@times, 1 - alpha, background);
    end
    
    %----- Get the list of associated objects, sans deleted items
    function sliders = getAssociates(handle)
      sliders                       = get(handle, 'UserData');
      sliders(~ishghandle(sliders)) = [];
      set(handle, 'UserData', sliders);
    end
      
    %----- Callback for pixel info display
    function updatePixelInfo(handle, event)
      
      movieSliders      = MovieSlider.getAssociates(handle);
      for iMov = 1:numel(movieSliders)
        if ~strcmp(get(movieSliders(iMov).tmrPlayback, 'Running'), 'off') || isempty(movieSliders(iMov).movie)
          continue;
        end
        
        mousePos        = round(get(movieSliders(iMov).axsMovie, 'CurrentPoint'));
        xRange          = rangemin( get(movieSliders(iMov).axsMovie, 'XLim'), [1, size(movieSliders(iMov).movie,2)] );
        yRange          = rangemin( get(movieSliders(iMov).axsMovie, 'YLim'), [1, size(movieSliders(iMov).movie,1)] );
        
        if      mousePos(1,2) >= yRange(1) && mousePos(1,2) <= yRange(2)    ...
            &&  mousePos(1,1) >= xRange(1) && mousePos(1,1) <= xRange(2)
          set ( movieSliders(iMov).txtInfo                                  ...
              , 'String'    , sprintf ( '(%d,%d,%d)=%.4g'                   ...
                                      , mousePos(1,2), mousePos(1,1), movieSliders(iMov).currentFrame                             ...
                                      , movieSliders(iMov).movie(mousePos(1,2), mousePos(1,1), movieSliders(iMov).currentFrame)   ...
                                      ) ...
              );
          return;
        end
      end
      
    end
    
    %----- Callback to start the zoom action
    function started = startZooming(handle, event)
      
      movieSliders      = MovieSlider.getAssociates(handle);
      started           = false;
      for iMov = 1:numel(movieSliders)
        clickType       = get(movieSliders(iMov).figParent, 'SelectionType');
        if ~strcmpi(clickType, 'alt')
          continue;
        end
        
        mousePos        = get(movieSliders(iMov).axsMovie, 'CurrentPoint');
        xRange          = get(movieSliders(iMov).axsMovie, 'XLim');
        yRange          = get(movieSliders(iMov).axsMovie, 'YLim');
        
        if      mousePos(1,2) >= yRange(1) && mousePos(1,2) <= yRange(2)     ...
            &&  mousePos(1,1) >= xRange(1) && mousePos(1,1) <= xRange(2)
          zoomExtended(movieSliders(iMov).figParent, movieSliders(iMov).axsMovie);
          started       = true;
          return;
        end
      end
      
    end
    
    
    %----- Callback for keyboard control of frame display
    function keyboardControl(handle, event)
      
      movieSliders      = MovieSlider.getAssociates(handle);
      if isempty(movieSliders)
        return;
      end
      
      selAxes           = get(handle, 'CurrentAxes');
      slider            = movieSliders([movieSliders.axsMovie] == selAxes);
      if isempty(slider)
        return;
      end
      
      switch event.Key
        case 'leftarrow'
          slider.shiftFrame(-1);
        case 'rightarrow'
          slider.shiftFrame(+1);
        case 'uparrow'
          slider.shiftFrame(-1);
        case 'downarrow'
          slider.shiftFrame(+1);
        case 'pageup'
          slider.shiftFrame(-MovieSlider.DEFAULT_FPS);
        case 'pagedown'
          slider.shiftFrame(+MovieSlider.DEFAULT_FPS);
        case 'home'
          slider.setFrame(1);
        case 'end'
          slider.setFrame(slider.totalFrames);
        case 'return'
          slider.togglePlayback(slider.btnPlay, event);
        case 'space'
          slider.togglePlayback(slider.btnPlay, event);
        case 'escape'
          if ~isempty(slider.fcnReturn)
            uicontrol(slider.txtDummy);
            slider.fcnReturn();
          end
      end
      
    end

    %----- Utility function to place MovieSlider on largest monitor
    function index = getMonitorBySize()
      monitors    = get(0,'monitor');
      screenArea  = prod( monitors(:,3:end), 2 );
      [~,index]   = max(screenArea);
    end
    
  end
  
end
