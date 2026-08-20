function result = automatedDesignAgent(varargin)
%AUTOMATEDDESIGNAGENT Prime / seed sequential design loop (MATLAB ZOS-API).
%
%   automatedDesignAgent('requirements', 'examples/minimal_imaging_requirements.json', ...
%                        'out', 'output/my-design')
%
%   Name-value: requirements, out, zosRoot, mode ('extension'|'standalone'), instanceId
    thisDir = fileparts(mfilename('fullpath'));
    addpath(thisDir, '-begin');

    if nargin < 1
        fprintf('Usage: automatedDesignAgent(''requirements'', path, ''out'', path, ...)\n');
        fprintf('  mode: extension (default) | standalone\n');
        return
    end

    defaults = struct( ...
        'requirements', '', ...
        'out', 'output/automated-zemax-design', ...
        'zosRoot', '', ...
        'mode', 'extension', ...
        'instanceId', 0);
    opts = zos.parseNameValue(defaults, varargin{:});
    if isempty(opts.requirements)
        error('zos:Args', 'requirements path is required.');
    end

    reqPath = zos.absPath(opts.requirements);
    req = zos.loadRequirements(reqPath);
    zoomCfgs = zos.localGet(req, 'constraints.zoom_configurations', []);
    if zos.countItems(zoomCfgs) > 0
        error('zos:WrongAgent', ...
            ['This requirements file has zoom_configurations. ', ...
             'Use zoomLensDesignAgent instead of automatedDesignAgent.']);
    end

    outDir = zos.ensureDir(opts.out);
    logPath = fullfile(outDir, 'design-log.jsonl');
    copyfile(reqPath, fullfile(outDir, 'requirements.json'));

    stages = {'baseline', 'feasibility', 'image-quality', 'field-balance', 'manufacturability'};
    stageLimit = zos.localGet(req, 'automation.max_stages', numel(stages));
    try
        stageLimit = max(1, min(numel(stages), double(stageLimit)));
    catch
        stageLimit = numel(stages);
    end
    stages = stages(1:stageLimit);
    retries = zos.localGet(req, 'automation.max_stage_retries', 2);
    retries = max(1, double(retries));
    optSeconds = zos.localGet(req, 'automation.max_optimization_seconds_per_stage', 120);

    result = struct('out_dir', outDir, 'log_path', logPath, 'stages', {{}}, 'final_lens', '');
    app = [];
    try
        [app, sys, info] = zos.connectZemax(opts);
        zos.appendJsonl(logPath, struct('event', 'connect', 'mode', info.mode, ...
            'instanceId', info.instanceId, 'licenseStatus', info.licenseStatus));

        [sys, seedContext] = zos.loadOrCreateSystem(app, req);
        zos.appendJsonl(logPath, seedEvent('seed-selected', seedContext));
        gaps = zos.localGet(seedContext.seed_design, 'structural_gaps', {});
        if zos.countItems(gaps) > 0
            zos.appendJsonl(logPath, struct('event', 'seed-structural-gaps', ...
                'count', zos.countItems(gaps), ...
                'family_hint', zos.localGet(seedContext.seed_design, 'family_hint', ''), ...
                'structural_gaps', gaps));
        end

        lastAcceptedMetrics = [];
        lastAcceptedLens = '';
        stageResults = {};

        for si = 1:numel(stages)
            stage = stages{si};
            zos.appendJsonl(logPath, struct('event', 'stage-start', 'stage', stage));
            nTry = 1;
            if ~strcmp(stage, 'baseline')
                nTry = retries;
            end
            accepted = false;
            stageResult = struct('name', stage, 'accepted', false);
            for attempt = 0:nTry-1
                if ~strcmp(stage, 'baseline')
                    if attempt > 0 && ~isempty(lastAcceptedLens)
                        sys.LoadFile(lastAcceptedLens, false);
                    end
                    plan = zos.configureVariablesAndMerit(sys, req, stage, attempt);
                    zos.appendJsonl(logPath, struct('event', 'stage-policy', ...
                        'stage', stage, 'attempt', attempt + 1, 'policy', plan));
                    opt = zos.runLocalOptimization(sys, 'seconds', optSeconds);
                    zos.appendJsonl(logPath, struct('event', 'optimize', ...
                        'stage', stage, 'status', opt.status));
                end
                stageResult = evaluatePrimeStage(sys, outDir, stage);
                decision = zos.decideStageAcceptance(lastAcceptedMetrics, ...
                    stageResult.metrics, stage, req);
                stageResult.accepted = logical(decision.accepted);
                stageResult.decision = decision;
                zos.writeJson(fullfile(outDir, ['stage-' stage '.json']), stageResult);
                zos.appendJsonl(logPath, struct('event', 'stage-decision', ...
                    'stage', stage, 'attempt', attempt + 1, 'decision', decision));
                if stageResult.accepted
                    lastAcceptedMetrics = stageResult.metrics;
                    lastAcceptedLens = stageResult.lens_path;
                    accepted = true;
                    break
                end
                if strncmp(char(decision.recovery_action), 'rollback', 8) && ~isempty(lastAcceptedLens)
                    sys.LoadFile(lastAcceptedLens, false);
                end
            end
            if ~accepted && ~isempty(lastAcceptedLens)
                try
                    sys.LoadFile(lastAcceptedLens, false);
                catch
                end
            end
            zos.appendJsonl(logPath, struct('event', 'stage-finish', 'stage', stage, ...
                'accepted', stageResult.accepted, 'lens_path', stageResult.lens_path));
            stageResults{end + 1} = stageResult; %#ok<AGROW>
        end

        result.stages = stageResults;
        result.final_lens = lastAcceptedLens;
        fprintf('\nDesign loop complete.\n  Output: %s\n  Final lens: %s\n  Log: %s\n', ...
            outDir, lastAcceptedLens, logPath);
    catch err
        zos.appendJsonl(logPath, struct('event', 'error', 'message', err.message));
        rethrow(err);
    end

    if strcmpi(char(opts.mode), 'standalone')
        zos.cleanupStandalone(app);
    end
end

function ev = seedEvent(name, seedContext)
    ev = struct('event', name);
    ev.selected_case = zos.localGet(seedContext.seed_design, 'selected_case', '');
    ev.selected_case_path = zos.localGet(seedContext.seed_design, 'selected_case_path', '');
    ev.family_hint = zos.localGet(seedContext.seed_design, 'family_hint', '');
    ev.provenance = zos.localGet(seedContext.seed_design, 'provenance', struct());
end

function stageResult = evaluatePrimeStage(sys, outDir, stage)
    analysisDir = fullfile(outDir, 'analyses', stage);
    files = zos.exportCommonAnalyses(sys, analysisDir);
    metrics = zos.parseMetrics(files);
    mv = zos.meritValue(sys);
    if ~isempty(mv)
        metrics.summary.merit_value = mv;
    end
    metricsPath = fullfile(outDir, ['metrics-' stage '.json']);
    zos.writeJson(metricsPath, metrics);
    lensPath = zos.saveSystemAs(sys, fullfile(outDir, [stage '.zmx']));
    stageResult = struct( ...
        'name', stage, ...
        'lens_path', lensPath, ...
        'metrics_path', metricsPath, ...
        'analysis_dir', analysisDir, ...
        'merit_value', metrics.summary.merit_value, ...
        'accepted', true, ...
        'metrics', metrics);
end
