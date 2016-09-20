%%
function [rMax] = rangemax(range1, range2)

  if numel(range2) == 1
    rMax  = [ min([range1(1) range2])     ...
            , max([range1(2) range2])     ...
            ];
  else
    rMax  = [ min([range1(1) range2(1)])  ...
            , max([range1(2) range2(2)])  ...
            ];
  end
  
end
