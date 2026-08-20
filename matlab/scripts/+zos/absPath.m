function p = absPath(p)
%ABSPATH Resolve a path against pwd. Warns on non-ASCII (SaveAs risk).
    p = char(p);
    if isempty(p)
        return
    end
    isAbs = ~isempty(regexp(p, '^[A-Za-z]:[\\/]', 'once')) || strncmp(p, '\\', 2) || strncmp(p, '/', 1);
    if ~isAbs
        p = fullfile(pwd, p);
    end
    try
        p = char(java.io.File(p).getCanonicalPath());
    catch
        % keep fullfile result
    end
    if any(double(p) > 127)
        warning('zos:NonAsciiPath', ...
            'Non-ASCII path may fail OpticStudio SaveAs/GetTextFile: %s', p);
    end
end
