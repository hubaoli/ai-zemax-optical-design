function appendJsonl(path, event)
%APPENDJSONL Append one JSON object as a line to a UTF-8 jsonl log.
    path = zos.absPath(path);
    parent = fileparts(path);
    if ~isempty(parent) && exist(parent, 'dir') ~= 7
        mkdir(parent);
    end
    if ~isfield(event, 'time')
        event.time = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss'));
    end
    fid = fopen(path, 'a', 'n', 'UTF-8');
    if fid < 0
        error('zos:IO', 'Cannot append %s', path);
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(event));
end
