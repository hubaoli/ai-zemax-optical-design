function cleanupStandalone(app)
%CLEANUPSTANDALONE Close a Standalone OpticStudio instance. Never use on Interactive Extension.
    if nargin < 1 || isempty(app)
        return
    end
    try
        app.CloseApplication();
    catch
    end
end
