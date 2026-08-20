function item = getItem(x, i)
%GETITEM Index into a JSON-decoded array (cell or struct/numeric array).
    if isempty(x)
        item = [];
    elseif iscell(x)
        item = x{i};
    else
        item = x(i);
    end
end
