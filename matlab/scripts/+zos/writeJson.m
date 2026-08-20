function writeJson(path, data)
%WRITEJSON Write UTF-8 JSON (pretty-print when the MATLAB release supports it).
    path = zos.absPath(path);
    parent = fileparts(path);
    if ~isempty(parent) && exist(parent, 'dir') ~= 7
        mkdir(parent);
    end
    try
        txt = jsonencode(data, 'PrettyPrint', true);
    catch
        txt = jsonencode(data);
    end
    fid = fopen(path, 'w', 'n', 'UTF-8');
    if fid < 0
        error('zos:IO', 'Cannot write %s', path);
    end
    cleaner = onCleanup(@() fclose(fid));
    fwrite(fid, txt, 'char');
end
