function p = ensureDir(p)
%ENSUREDIR Create a directory (and parents) if needed. Returns absolute path.
    p = zos.absPath(p);
    if exist(p, 'dir') ~= 7
        mkdir(p);
    end
end
