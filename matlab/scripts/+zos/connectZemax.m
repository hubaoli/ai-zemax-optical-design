function [app, sys, info] = connectZemax(varargin)
%CONNECTZEMAX Connect to OpticStudio via MATLAB ZOS-API (.NET).
%
%   [app, sys, info] = zos.connectZemax()
%   [app, sys, info] = zos.connectZemax('mode', 'extension', 'instanceId', 0)
%   [app, sys, info] = zos.connectZemax('mode', 'standalone', 'zosRoot', 'C:\Program Files\...')
%
%   mode: 'extension' (default) | 'standalone'
%   Interactive Extension must NOT call CloseApplication on app.
    defaults = struct( ...
        'mode', 'extension', ...
        'instanceId', 0, ...
        'zosRoot', '');
    opts = zos.parseNameValue(defaults, varargin{:});
    mode = lower(char(opts.mode));
    instanceId = int32(opts.instanceId);

    asm = zos.loadAssemblies(opts.zosRoot);

    TheConnection = ZOSAPI.ZOSAPI_Connection();
    if strcmp(mode, 'standalone')
        app = TheConnection.CreateNewApplication();
    else
        mode = 'extension';
        app = TheConnection.ConnectAsExtension(instanceId);
    end

    if isempty(app)
        error('zos:Connect', 'Failed to connect to OpticStudio in %s mode.', mode);
    end

    licensed = false;
    try
        licensed = logical(app.IsValidLicenseForAPI);
    catch
    end
    if ~licensed
        error('zos:License', ...
            'Connected in %s mode, but IsValidLicenseForAPI is false.', mode);
    end

    sys = [];
    try
        sys = app.PrimarySystem;
    catch
    end
    if isempty(sys)
        error('zos:PrimarySystem', ...
            'Connected in %s mode, but PrimarySystem is not available.', mode);
    end

    info = struct();
    info.mode = mode;
    info.instanceId = double(instanceId);
    info.netHelper = asm.netHelper;
    info.installDir = asm.installDir;
    info.zemaxDirectory = asm.zemaxDirectory;
    info.licenseOk = true;
    info.licenseStatus = '';
    try
        info.licenseStatus = char(app.LicenseStatus.ToString());
    catch
        try
            info.licenseStatus = char(app.LicenseStatus);
        catch
        end
    end
    try
        if isempty(info.zemaxDirectory)
            info.zemaxDirectory = char(ZOSAPI_NetHelper.ZOSAPI_Initializer.GetZemaxDirectory());
        end
    catch
    end
end
