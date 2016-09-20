%%
function [rMin] = rangemin(range1, range2)

  rMin  = [ max([range1(1) range2(1)])  ...
          , min([range1(2) range2(2)])  ...
          ];
  
end
