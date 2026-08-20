function info = connectionSmokeTest(varargin)
%CONNECTIONSMOKETEST Verify MATLAB ZOS-API connection.
%
%   connectionSmokeTest
%   connectionSmokeTest('mode', 'extension', 'instanceId', 0)
%   connectionSmokeTest('mode', 'standalone', 'zosRoot', 'C:\Program Files\...')
%
%   OpticStudio must be open and Interactive Extension started unless mode=standalone.
    thisDir = fileparts(mfilename('fullpath'));
    addpath(thisDir, '-begin');

    defaults = struct('mode', 'extension', 'instanceId', 0, 'zosRoot', '');
    opts = zos.parseNameValue(defaults, varargin{:});

    app = [];
    try
        [app, sys, info] = zos.connectZemax(opts);
        fprintf('Connected: yes\n');
        fprintf('Mode: %s\n', info.mode);
        fprintf('InstanceId: %g\n', info.instanceId);
        fprintf('IsValidLicenseForAPI: true\n');
        fprintf('LicenseStatus: %s\n', info.licenseStatus);
        fprintf('PrimarySystem: ok\n');
        fprintf('ZemaxDirectory: %s\n', info.zemaxDirectory);
        fprintf('Primary system type: %s\n', class(sys));
    catch err
        fprintf('Connected: no\n');
        fprintf('Mode: %s\n', char(opts.mode));
        fprintf('InstanceId: %g\n', opts.instanceId);
        fprintf('Error: %s\n', err.message);
        rethrow(err);
    end

    if strcmpi(char(opts.mode), 'standalone')
        zos.cleanupStandalone(app);
        fprintf('Standalone application closed.\n');
    end
end
