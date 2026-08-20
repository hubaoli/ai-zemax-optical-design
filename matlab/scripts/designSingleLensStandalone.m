function summary = designSingleLensStandalone(varargin)
%DESIGNSINGLELENSSTANDALONE Lightweight N-BK7 singlet via MATLAB ZOS-API.
%
%   Default mode is Interactive Extension (OpticStudio must be open).
%   Pass 'mode','standalone' to launch a headless instance.
%
%   designSingleLensStandalone('out', 'output/singlet', 'eflMm', 50, 'fNumber', 4)
    thisDir = fileparts(mfilename('fullpath'));
    addpath(thisDir, '-begin');

    defaults = struct( ...
        'out', 'output/singlet', ...
        'zosRoot', '', ...
        'mode', 'extension', ...
        'instanceId', 0, ...
        'fNumber', 4.0, ...
        'fieldDeg', 5.0, ...
        'eflMm', 50.0);
    opts = zos.parseNameValue(defaults, varargin{:});
    outDir = zos.ensureDir(opts.out);
    logPath = fullfile(outDir, 'design-log.jsonl');

    app = [];
    try
        [app, sys, info] = zos.connectZemax(opts);
        zos.appendJsonl(logPath, struct('event', 'single_lens_start', ...
            'mode', info.mode, 'instanceId', info.instanceId));

        sys.New(false);
        zos.setAperture(sys, struct('type', 'f_number', 'value', opts.fNumber));
        zos.setWavelengths(sys, [ ...
            struct('value', 0.5875618, 'weight', 1), ...
            struct('value', 0.4861327, 'weight', 1), ...
            struct('value', 0.6562725, 'weight', 1)]);
        zos.setFields(sys, [ ...
            struct('type', 'angle_deg', 'value', 0, 'weight', 1), ...
            struct('type', 'angle_deg', 'value', opts.fieldDeg, 'weight', 1)]);

        lde = sys.LDE;
        while lde.NumberOfSurfaces < 5
            lde.InsertNewSurfaceAt(int32(max(1, lde.NumberOfSurfaces - 1)));
        end
        try
            sys.LDE.StopSurface = int32(1);
        catch
        end
        stop = lde.GetSurfaceAt(int32(1));
        front = lde.GetSurfaceAt(int32(2));
        back = lde.GetSurfaceAt(int32(3));
        stop.Thickness = 0.0;
        front.Radius = 50.0;
        front.Thickness = 5.0;
        front.Material = 'N-BK7';
        back.Radius = -50.0;
        back.Thickness = 45.0;
        back.Material = '';
        front.RadiusCell.MakeSolveVariable();
        back.RadiusCell.MakeSolveVariable();
        back.ThicknessCell.MakeSolveVariable();

        beforePath = zos.saveSystemAs(sys, fullfile(outDir, 'single-lens-before-optimization.zmx'));

        try
            sys.MFE.DeleteAllRows();
        catch
        end
        zos.applyOptimizationWizard(sys, 'data', 1, 'ring', 2, 'arm', 0);
        try
            op = sys.MFE.AddOperand();
            op.ChangeType(ZOSAPI.Editors.MFE.MeritOperandType.EFFL);
            op.Target = double(opts.eflMm);
            op.Weight = 10.0;
        catch
        end

        opt = zos.runLocalOptimization(sys);
        afterPath = zos.saveSystemAs(sys, fullfile(outDir, 'single-lens-after-optimization.zmx'));
        files = zos.exportCommonAnalyses(sys, fullfile(outDir, 'analyses'));

        summary = struct( ...
            'event', 'single_lens_finish', ...
            'before_lens', beforePath, ...
            'after_lens', afterPath, ...
            'optimization_status', opt.status, ...
            'merit_initial', opt.initial, ...
            'merit_final', opt.final, ...
            'analyses', {files});
        zos.appendJsonl(logPath, summary);
        zos.writeJson(fullfile(outDir, 'summary.json'), summary);
        fprintf('%s\n', jsonencode(summary));
    catch err
        zos.appendJsonl(logPath, struct('event', 'error', 'message', err.message));
        rethrow(err);
    end

    if strcmpi(char(opts.mode), 'standalone')
        zos.cleanupStandalone(app);
    end
end
