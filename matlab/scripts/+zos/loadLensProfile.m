function profile = loadLensProfile(req, reqDir)
%LOADLENSPROFILE Load requirements.lens_profile from path or inline struct.
    ref = zos.localGet(req, 'lens_profile', []);
    if isempty(ref)
        ref = zos.localGet(req, 'lens_profile_path', []);
    end
    if isstruct(ref) && ~isempty(fieldnames(ref))
        profile = zos.normalizeLensProfile(ref);
        return
    end
    if ischar(ref) || isstring(ref)
        p = strtrim(char(ref));
        if ~isempty(p)
            if ~isempty(reqDir) && isempty(regexp(p, '^[A-Za-z]:[\\/]', 'once'))
                p = fullfile(char(reqDir), p);
            end
            p = zos.absPath(p);
            if exist(p, 'file') ~= 2
                error('zos:Profile', 'lens_profile file not found: %s', p);
            end
            profile = zos.normalizeLensProfile(jsondecode(fileread(p)));
            profile.source_path = p;
            return
        end
    end
    error('zos:Profile', ...
        'Zoom design blocked: lens_profile is required. Do not invent a zoom architecture.');
end
