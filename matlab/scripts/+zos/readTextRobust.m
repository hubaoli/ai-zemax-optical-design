function txt = readTextRobust(path)
%READTEXTROBUST Read Zemax analysis text (UTF-16 with BOM, then UTF-8).
    path = zos.absPath(path);
    fid = fopen(path, 'rb');
    if fid < 0
        txt = '';
        return
    end
    cleaner = onCleanup(@() fclose(fid));
    bytes = fread(fid, inf, '*uint8');
    if numel(bytes) >= 2 && bytes(1) == 255 && bytes(2) == 254
        txt = native2unicode(bytes(:).', 'UTF-16LE');
        return
    end
    if numel(bytes) >= 2 && bytes(1) == 254 && bytes(2) == 255
        txt = native2unicode(bytes(:).', 'UTF-16BE');
        return
    end
    try
        txt = native2unicode(bytes(:).', 'UTF-8');
    catch
        txt = native2unicode(bytes(:).', 'latin1');
    end
end
