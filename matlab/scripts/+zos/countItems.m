function n = countItems(x)
%COUNTITEMS Length of a JSON-decoded array (struct array, cell, or numeric).
    if isempty(x)
        n = 0;
    else
        n = numel(x);
    end
end
