function v = localGet(s, path, default)
%LOCALGET Read a possibly nested struct field. JSON null ([]) yields default.
    if nargin < 3
        default = [];
    end
    v = default;
    if isempty(s) || (~isstruct(s) && ~isobject(s))
        return
    end
    parts = strsplit(char(path), '.');
    cur = s;
    for i = 1:numel(parts)
        name = parts{i};
        if ~isstruct(cur)
            return
        end
        if ~isfield(cur, name)
            alt = matlab.lang.makeValidName(name);
            if ~strcmp(alt, name) && isfield(cur, alt)
                name = alt;
            else
                return
            end
        end
        cur = cur.(name);
    end
    if isnumeric(cur) && isempty(cur)
        v = default;
    else
        v = cur;
    end
end
