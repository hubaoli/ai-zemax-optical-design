function opts = parseNameValue(defaults, varargin)
%PARSENAMEVALUE Merge name-value pairs or a struct into defaults.
    opts = defaults;
    if nargin < 2 || isempty(varargin)
        return
    end
    if numel(varargin) == 1 && isstruct(varargin{1})
        src = varargin{1};
        names = fieldnames(src);
        for i = 1:numel(names)
            opts.(names{i}) = src.(names{i});
        end
        return
    end
    if mod(numel(varargin), 2) ~= 0
        error('zos:Args', 'Expected name-value pairs or a single struct.');
    end
    for i = 1:2:numel(varargin)
        name = char(varargin{i});
        opts.(name) = varargin{i + 1};
    end
end
