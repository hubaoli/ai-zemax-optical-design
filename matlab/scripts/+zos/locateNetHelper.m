function [netHelper, installDir] = locateNetHelper(zosRoot)
%LOCATENETHELPER Find ZOSAPI_NetHelper.dll and an optional install directory.
    netHelper = '';
    installDir = '';
    cands = {};

    if nargin >= 1 && ~isempty(zosRoot)
        zosRoot = char(zosRoot);
        if exist(zosRoot, 'file') == 2 && ~isempty(regexpi(zosRoot, 'ZOSAPI_NetHelper\.dll$'))
            cands{end + 1} = zosRoot; %#ok<AGROW>
        else
            cands{end + 1} = fullfile(zosRoot, 'ZOS-API', 'Libraries', 'ZOSAPI_NetHelper.dll'); %#ok<AGROW>
            cands{end + 1} = fullfile(zosRoot, 'ZOSAPI_NetHelper.dll'); %#ok<AGROW>
            installDir = zosRoot;
        end
    end

    try
        zemaxData = winqueryreg('HKEY_CURRENT_USER', 'Software\Zemax', 'ZemaxRoot');
        cands{end + 1} = fullfile(char(zemaxData), 'ZOS-API', 'Libraries', 'ZOSAPI_NetHelper.dll'); %#ok<AGROW>
    catch
    end

    extra = { ...
        'C:\Program Files\Ansys Zemax OpticStudio 2024 R1.00\ZOS-API\Libraries\ZOSAPI_NetHelper.dll', ...
        'C:\Program Files\Ansys Zemax OpticStudio\ZOS-API\Libraries\ZOSAPI_NetHelper.dll', ...
        'C:\Program Files\Zemax OpticStudio\ZOS-API\Libraries\ZOSAPI_NetHelper.dll'};
    cands = [cands, extra];

    for i = 1:numel(cands)
        if exist(cands{i}, 'file') == 2
            netHelper = cands{i};
            break
        end
    end

    if isempty(netHelper)
        error('zos:NetHelper', ...
            'ZOSAPI_NetHelper.dll not found. Pass ''zosRoot'' as the OpticStudio install directory.');
    end

    if isempty(installDir)
        % Libraries\ -> ZOS-API\ -> install root
        libDir = fileparts(netHelper);
        zosApiDir = fileparts(libDir);
        parent = fileparts(zosApiDir);
        if exist(fullfile(parent, 'ZOSAPI.dll'), 'file') == 2 || exist(fullfile(parent, 'OpticStudio.exe'), 'file') == 2
            installDir = parent;
        end
    end
end
