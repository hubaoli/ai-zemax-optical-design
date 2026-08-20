function info = loadAssemblies(zosRoot)
%LOADASSEMBLIES Idempotent ZOS-API .NET assembly load for this MATLAB session.
    persistent loaded key
    [netHelper, installDir] = zos.locateNetHelper(zosRoot);
    token = lower(netHelper);

    if ~isempty(loaded) && loaded && strcmp(key, token)
        info = struct('netHelper', netHelper, 'installDir', installDir, 'zemaxDirectory', '');
        try
            info.zemaxDirectory = char(ZOSAPI_NetHelper.ZOSAPI_Initializer.GetZemaxDirectory());
        catch
        end
        return
    end

    import System.Reflection.*
    NET.addAssembly(netHelper);

    ok = 0;
    if ~isempty(installDir) && exist(installDir, 'dir') == 7
        try
            ok = ZOSAPI_NetHelper.ZOSAPI_Initializer.Initialize(installDir);
        catch
            ok = 0;
        end
    end
    if ok ~= 1
        ok = ZOSAPI_NetHelper.ZOSAPI_Initializer.Initialize();
    end
    if ok ~= 1
        error('zos:Init', 'ZOSAPI_NetHelper failed to initialize OpticStudio.');
    end

    NET.addAssembly(AssemblyName('ZOSAPI_Interfaces'));
    NET.addAssembly(AssemblyName('ZOSAPI'));

    loaded = true;
    key = token;

    info = struct('netHelper', netHelper, 'installDir', installDir, 'zemaxDirectory', '');
    try
        info.zemaxDirectory = char(ZOSAPI_NetHelper.ZOSAPI_Initializer.GetZemaxDirectory());
    catch
    end
end
