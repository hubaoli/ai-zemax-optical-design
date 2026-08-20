function path = saveSystemAs(sys, path)
%SAVESYSTEMAS SaveAs with an absolute path. Relative / non-ASCII paths may fail silently.
    path = zos.absPath(path);
    parent = fileparts(path);
    if ~isempty(parent) && exist(parent, 'dir') ~= 7
        mkdir(parent);
    end
    sys.SaveAs(path);
end
