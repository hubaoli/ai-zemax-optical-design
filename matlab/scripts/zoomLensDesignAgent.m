function result = zoomLensDesignAgent(varargin)
%ZOOMLENSDESIGNAGENT Profile-driven multi-configuration zoom design loop.
%
%   zoomLensDesignAgent('requirements', 'examples/apsc_18-55_f1.4_zoom_requirements.json', ...
%                       'out', 'output/aps-c-zoom')
%
%   Name-value: requirements, out, zosRoot, mode ('extension'|'standalone'), instanceId
%
%   Requires requirements.lens_profile. Does not invent a zoom architecture.
    thisDir = fileparts(mfilename('fullpath'));
    addpath(thisDir, '-begin');

    if nargin < 1
        fprintf('Usage: zoomLensDesignAgent(''requirements'', path, ''out'', path, ...)\n');
        return
    end

    defaults = struct( ...
        'requirements', '', ...
        'out', 'output/zoom-lens-design', ...
        'zosRoot', '', ...
        'mode', 'extension', ...
        'instanceId', 0);
    opts = zos.parseNameValue(defaults, varargin{:});
    if isempty(opts.requirements)
        error('zos:Args', 'requirements path is required.');
    end

    reqPath = zos.absPath(opts.requirements);
    req = zos.loadRequirements(reqPath);
    reqDir = fileparts(reqPath);
    zoomConfigs = zos.localGet(req, 'constraints.zoom_configurations', []);
    if zos.countItems(zoomConfigs) < 1
        error('zos:Zoom', 'No zoom_configurations in requirements.');
    end
    profile = zos.loadLensProfile(req, reqDir);

    outDir = zos.ensureDir(opts.out);
    logPath = fullfile(outDir, 'design-log.jsonl');
    copyfile(reqPath, fullfile(outDir, 'requirements.json'));
    zos.writeJson(fullfile(outDir, 'lens-profile.normalized.json'), profile);

    stages = {'baseline', 'feasibility', 'image-quality', 'field-balance', 'manufacturability'};
    stageLimit = zos.localGet(req, 'automation.max_stages', numel(stages));
    try
        stageLimit = max(1, min(numel(stages), double(stageLimit)));
    catch
        stageLimit = numel(stages);
    end
    stages = stages(1:stageLimit);
    optSeconds = zos.localGet(req, 'automation.max_optimization_seconds_per_stage', 300);

    fprintf('========================================================================\n');
    fprintf('ZOOM LENS AUTOMATED DESIGN (MATLAB ZOS-API)\n');
    fprintf('  Profile: %s\n', char(profile.name));
    fprintf('  Configs: %g\n', zos.countItems(zoomConfigs));
    for i = 1:zos.countItems(zoomConfigs)
        c = zos.getItem(zoomConfigs, i);
        fprintf('    %s: EFL=%gmm F/%g\n', char(zos.localGet(c, 'name', '')), ...
            zos.localGet(c, 'efl_mm', []), zos.localGet(c, 'f_number', []));
    end
    fprintf('  Output:  %s\n', outDir);
    fprintf('========================================================================\n');

    result = struct('out_dir', outDir, 'log_path', logPath, 'profile', char(profile.name), ...
        'stages', {{}}, 'final_lens', '');
    app = [];
    try
        fprintf('\n[1/5] Connecting to Zemax OpticStudio...\n');
        [app, sys, info] = zos.connectZemax(opts);
        zos.appendJsonl(logPath, struct('event', 'connect', 'mode', info.mode, ...
            'instanceId', info.instanceId, 'licenseStatus', info.licenseStatus));
        fprintf('  Connected via %s.\n', info.mode);

        fprintf('\n[2/5] Building profile-driven zoom starting prescription...\n');
        zos.appendJsonl(logPath, struct('event', 'profile-load', 'name', char(profile.name), ...
            'source_path', zos.localGet(profile, 'source_path', '')));
        sys.New(false);
        zos.setWavelengths(sys, zos.localGet(req, 'wavelengths_um', []));
        zos.setFields(sys, zos.localGet(req, 'fields', []));
        zos.setAperture(sys, zos.localGet(req, 'aperture', struct()));
        zos.buildZoomPrescription(sys, profile);
        zos.setupZoomMce(sys, zoomConfigs, profile);

        fprintf('\n[3/5] Starting staged optimization loop...\n');
        lastLens = '';
        stageResults = {};
        for si = 1:numel(stages)
            stage = stages{si};
            fprintf('\n  ============================================================\n');
            fprintf('  STAGE %d/%d: %s\n', si, numel(stages), upper(stage));
            fprintf('  ============================================================\n');
            zos.appendJsonl(logPath, struct('event', 'stage-start', 'stage', stage));

            merit = [];
            if ~strcmp(stage, 'baseline')
                zos.configureZoomVariables(sys, profile, stage);
                zos.buildZoomMeritFunction(sys, req, zoomConfigs, stage, profile);
                fprintf('  Optimizing (soft max %gs)...\n', double(optSeconds));
                opt = zos.runLocalOptimization(sys, 'seconds', optSeconds);
                merit = opt.final;
                if isempty(merit)
                    merit = zos.meritValue(sys);
                end
                if isempty(merit)
                    fprintf('  Final merit: (unavailable)\n');
                else
                    fprintf('  Final merit: %.6f\n', merit);
                end
            else
                zos.buildZoomMeritFunction(sys, req, zoomConfigs, stage, profile);
                merit = zos.meritValue(sys);
                if ~isempty(merit)
                    fprintf('  Baseline merit: %.6f\n', merit);
                end
            end

            sr = evaluateZoomStage(sys, outDir, stage, zoomConfigs, merit);
            lastLens = sr.lens_path;
            zos.appendJsonl(logPath, struct('event', 'stage-finish', 'stage', stage, ...
                'merit_value', merit, 'lens_path', sr.lens_path, ...
                'num_analyses', zos.countItems(sr.analysis_files)));
            fprintf('  Saved: %s\n', sr.lens_path);
            stageResults{end + 1} = sr; %#ok<AGROW>
        end

        result.stages = stageResults;
        result.final_lens = lastLens;
        fprintf('\n[4/5] Design loop complete!\n  Outputs in: %s\n', outDir);
        fprintf('\n[5/5] Key files:\n  Final lens:   %s\n  Design log:   %s\n  Analyses:     %s\n', ...
            lastLens, logPath, fullfile(outDir, 'analyses'));
        fprintf('\nReview in OpticStudio: MTF per config, cam curves, distortion at wide, glass.\n');
    catch err
        zos.appendJsonl(logPath, struct('event', 'error', 'message', err.message));
        rethrow(err);
    end

    if strcmpi(char(opts.mode), 'standalone')
        fprintf('\nClosing Standalone OpticStudio...\n');
        zos.cleanupStandalone(app);
    end
end

function sr = evaluateZoomStage(sys, outDir, stage, zoomConfigs, merit)
    analysisDir = fullfile(outDir, 'analyses', stage);
    files = zos.exportZoomAnalyses(sys, analysisDir, zoomConfigs);
    metrics = struct( ...
        'stage', stage, ...
        'merit_function_value', merit, ...
        'num_configurations', zos.countItems(zoomConfigs), ...
        'num_analyses', numel(files), ...
        'analysis_files', {files});
    parsed = zos.parseMetrics(files);
    metrics.summary = parsed.summary;
    metrics.parser_notes = parsed.parser_notes;
    metricsPath = fullfile(outDir, ['metrics-' stage '.json']);
    zos.writeJson(metricsPath, metrics);
    lensPath = zos.saveSystemAs(sys, fullfile(outDir, ['zoom_' stage '.zmx']));
    sr = struct( ...
        'name', stage, ...
        'lens_path', lensPath, ...
        'metrics_path', metricsPath, ...
        'analysis_dir', analysisDir, ...
        'merit_value', merit, ...
        'accepted', true, ...
        'analysis_files', {files});
    zos.writeJson(fullfile(outDir, ['stage-' stage '.json']), sr);
end
