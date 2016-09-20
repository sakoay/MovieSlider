%% RECTANGLECORNERS   Returns patch x and y coordinates for a rectangle with corner at (x,y) and with the given width/height
function [cornerX, cornerY] = rectangleCorners(x, y, width, height, doClose)

  if nargin < 5
    doClose = false;
  end
  if isempty(width)
    width   = 0;
  end
  if isempty(height)
    height  = 0;
  end
  
  % Canonical format of arguments
  x         = x(:)';
  y         = y(:)';
  width     = width(:)';
  height    = height(:)';
  
  % Equalize sizes
  if numel(x) == 1 && numel(y) > 1
    x       = x * ones(size(y));
  elseif numel(y) == 1 && numel(x) > 1
    y       = y * ones(size(x));
  end  
  
  cornerX   = [ x             ...
              ; x + width     ...
              ; x + width     ...
              ; x             ...
              ];
  cornerY   = [ y + height    ...
              ; y + height    ...
              ; y             ...
              ; y             ...
              ];

  if doClose
    cornerX(end+1,:)  = cornerX(1,:);
    cornerY(end+1,:)  = cornerY(1,:);
  end
  
end
