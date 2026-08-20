function buildZoomMeritFunction(sys, req, zoomConfigs, stage, profile)
%BUILDZOOMMERITFUNCTION Wizard base + per-config EFFL/WFNO/REAY + manufacturing.
    mfe = sys.MFE;
    try
        mfe.DeleteAllRows();
    catch
    end

    ok = zos.applyOptimizationWizard(sys, ...
        'data', 1, 'ring', 2, 'arm', 0, ...
        'glassMin', 1.5, 'glassMax', 8.0, 'glassEdge', 2.0, ...
        'airMin', 1.0, 'airMax', 50.0, 'airEdge', 0.5);
    if ok
        fprintf('  Optimization wizard applied.\n');
    else
        fprintf('  [WARN] Optimization wizard failed; continuing with manual operands.\n');
    end

    wmap = struct('feasibility', 10, 'imagequality', 5, ...
        'fieldbalance', 3, 'manufacturability', 2, 'baseline', 10);
    key = regexprep(stage, '[^a-zA-Z]', '');
    if isfield(wmap, key)
        w = wmap.(key);
    else
        w = 5;
    end

    bflTarget = zos.localGet(req, 'targets.bfl_mm', 25.0);
    ttlTarget = zos.localGet(req, 'targets.total_track_mm', 180.0);
    imgH = zos.localGet(req, 'targets.image_height_mm', 14.17);
    bflSurf = double(zos.localGet(profile, 'merit.bfl_surface', 11));
    maxField = double(zos.localGet(profile, 'merit.max_field_index', 3));
    distTarget = zos.localGet(req, 'targets.distortion_percent_max', 2.0);

    nCfg = zos.countItems(zoomConfigs);
    for c = 1:nCfg
        cfg = zos.getItem(zoomConfigs, c);
        efl = double(zos.localGet(cfg, 'efl_mm', zos.localGet(req, 'targets.efl_mm', 50)));
        fno = double(zos.localGet(cfg, 'f_number', 1.4));
        addTyped(mfe, 'EFFL', efl, w, c);
        addTyped(mfe, 'WFNO', fno, w * 0.5, c);
        addTyped(mfe, 'REAY', double(zos.localGet(cfg, 'image_height_mm', imgH)), w * 0.3, c, maxField);
    end
    addTyped(mfe, 'TOTR', double(ttlTarget), w * 0.1, 0);
    addTyped(mfe, 'CTVA', double(bflTarget), w * 0.5, 0, bflSurf);
    addTyped(mfe, 'AXCL', 0.0, w * 0.3, 0);
    addTyped(mfe, 'LACL', 0.0, w * 0.3, 0);

    if any(strcmp(stage, {'field-balance', 'manufacturability'})) && ~isempty(distTarget)
        for c = 1:nCfg
            addTyped(mfe, 'DIMX', double(distTarget), 1.0, c, maxField);
        end
    end

    if strcmp(stage, 'manufacturability')
        minCt = double(zos.localGet(req, 'constraints.min_center_thickness_mm', 0.8));
        minAg = double(zos.localGet(req, 'constraints.min_air_gap_mm', 0.1));
        maxDiam = double(zos.localGet(req, 'constraints.max_diameter_mm', 85.0));
        addTyped(mfe, 'MNCT', minCt, 5, 0);
        addTyped(mfe, 'MNET', 0.5, 3, 0);
        addTyped(mfe, 'MNEA', minAg, 3, 0);
        addTyped(mfe, 'MXSD', maxDiam / 2, 1, 0);
        addTyped(mfe, 'MNEG', 0.5, 3, 0);
        addTyped(mfe, 'GCOS', 0.0, 0.1, 0);
    end

    mv = zos.meritValue(sys);
    if ~isempty(mv)
        fprintf('  Initial merit function value: %.6f\n', mv);
    end
    fprintf('  Merit function built: stage=''%s''\n', stage);
end

function addTyped(mfe, typeName, target, weight, conf, extra)
    if nargin < 6
        extra = [];
    end
    try
        opType = ZOSAPI.Editors.MFE.MeritOperandType.(typeName);
        op = mfe.AddOperand();
        op.ChangeType(opType);
        op.Target = double(target);
        op.Weight = double(weight);
        if conf > 0
            zos.setOperandCell(op, 12, conf);
        end
        if ~isempty(extra)
            zos.setOperandCell(op, 3, extra);
        end
        if strcmp(typeName, 'EFFL') || strcmp(typeName, 'REAY')
            zos.setOperandCell(op, 2, 0);
        end
    catch err
        warning('zos:Merit', 'Operand %s failed: %s', typeName, err.message);
    end
end
