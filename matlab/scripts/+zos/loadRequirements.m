function req = loadRequirements(path)
%LOADREQUIREMENTS Read a UTF-8 requirements JSON (shared schema with Python examples/).
    path = zos.absPath(path);
    raw = fileread(path);
    req = jsondecode(raw);
    if ~isfield(req, 'assumptions') || isempty(req.assumptions)
        req.assumptions = {};
    end
    if ~isfield(req, 'automation') || isempty(req.automation)
        req.automation = struct();
    end
    req.source_path = path;
end
