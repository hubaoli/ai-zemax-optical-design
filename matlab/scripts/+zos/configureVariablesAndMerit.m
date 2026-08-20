function plan = configureVariablesAndMerit(sys, req, stage, recoveryLevel)
%CONFIGUREVARIABLESANDMERIT Staged variables + wizard/first-order targets for prime/seed designs.
    if nargin < 4
        recoveryLevel = 0;
    end
    lde = sys.LDE;
    nSurf = double(lde.NumberOfSurfaces);
    plan = buildPlan(nSurf, req, stage, recoveryLevel);

    if ~strcmp(stage, 'baseline')
        try
            sys.Tools.RemoveAllVariables();
        catch
        end
        for i = 1:numel(plan.surface_release_order)
            idx = plan.surface_release_order(i);
            try
                s = lde.GetSurfaceAt(int32(idx));
                s.RadiusCell.MakeSolveVariable();
                if any(plan.thickness_surfaces == idx)
                    s.ThicknessCell.MakeSolveVariable();
                end
                if any(plan.material_surfaces == idx)
                    try
                        s.MaterialCell.MakeSolveVariable();
                    catch
                    end
                end
            catch
            end
        end
        try
            sys.MFE.DeleteAllRows();
        catch
        end
        zos.applyOptimizationWizard(sys);
        addFirstOrder(sys, req, stage);
    end
end

function plan = buildPlan(nSurf, req, stage, recoveryLevel)
    family = lower(char(zos.localGet(req, 'seed_design.family_hint', '')));
    switch stage
        case 'baseline'
            active = [1, 2]; thick = []; mat = [];
        case 'feasibility'
            active = unique([1, 2, max(2, nSurf - 2)]);
            thick = 2; mat = [];
        case 'image-quality'
            active = activeWindow(nSurf, 4);
            thick = unique([2, max(2, nSurf - 2)]);
            mat = materialWindow(nSurf, family, true);
        case 'field-balance'
            active = activeWindow(nSurf, 5);
            thick = unique([2, max(2, floor(nSurf / 2))]);
            mat = materialWindow(nSurf, family, true);
        otherwise  % manufacturability
            active = unique([1, 2, max(2, nSurf - 2)]);
            thick = 2;
            mat = materialWindow(nSurf, family, false);
    end
    if recoveryLevel > 0
        shrink = min(recoveryLevel, max(1, numel(active) - 1));
        active = active(1:max(1, numel(active) - shrink));
        if ~isempty(thick)
            thick = thick(1:max(1, numel(thick) - shrink + 1));
        end
        if ~isempty(mat)
            mat = mat(1:max(1, numel(mat) - shrink + 1));
        end
    end
    active = active(active >= 1 & active < nSurf);
    thick = thick(thick >= 1 & thick < nSurf);
    mat = mat(mat >= 1 & mat < nSurf);
    plan = struct();
    plan.stage = stage;
    plan.recovery_level = recoveryLevel;
    plan.family_hint = zos.localGet(req, 'seed_design.family_hint', '');
    plan.active_surfaces = active;
    plan.thickness_surfaces = thick;
    plan.material_surfaces = mat;
    plan.surface_release_order = active;
    plan.variable_groups = {'powered_curvatures'};
    if any(strcmp(stage, {'feasibility', 'image-quality', 'field-balance'}))
        plan.variable_groups{end + 1} = 'air_spacings';
    end
end

function idx = activeWindow(nSurf, width)
    if nSurf <= 0
        idx = [];
        return
    end
    upper = min(nSurf - 1, max(2, width));
    idx = 1:upper;
end

function idx = materialWindow(nSurf, family, allowMore)
    if nSurf <= 0
        idx = [];
        return
    end
    if contains(family, 'zoom') && allowMore
        idx = unique([2, max(2, floor(nSurf / 2)), max(2, nSurf - 2)]);
    else
        idx = max(2, floor(nSurf / 2));
    end
end

function addFirstOrder(sys, req, stage)
    switch stage
        case 'feasibility', w = 10;
        case 'image-quality', w = 5;
        case 'field-balance', w = 3;
        case 'manufacturability', w = 2;
        otherwise, w = 5;
    end

    efl = zos.localGet(req, 'targets.efl_mm', []);
    bfl = zos.localGet(req, 'targets.bfl_mm', []);
    ttl = zos.localGet(req, 'targets.total_track_mm', []);
    fno = zos.localGet(req, 'aperture.value', []);
    dist = zos.localGet(req, 'targets.distortion_percent_max', []);
    minCt = zos.localGet(req, 'constraints.min_center_thickness_mm', 0.8);
    minAg = zos.localGet(req, 'constraints.min_air_gap_mm', 0.1);

    addOp(sys, 'EFFL', efl, w);
    if strcmpi(char(zos.localGet(req, 'aperture.type', 'f_number')), 'f_number')
        addOp(sys, 'WFNO', fno, w * 0.5);
    end
    addOp(sys, 'TOTR', ttl, w * 0.1);
    addOp(sys, 'CTVA', bfl, w * 0.5);
    if any(strcmp(stage, {'field-balance', 'manufacturability'}))
        addOp(sys, 'DIMX', dist, 1.0);
    end
    if strcmp(stage, 'manufacturability')
        addOp(sys, 'MNCT', minCt, 5);
        addOp(sys, 'MNEA', minAg, 3);
        addOp(sys, 'MNET', 0.5, 3);
    end
end

function addOp(sys, typeName, target, weight)
    if isempty(target) && ~strcmp(typeName, 'AXCL')
        return
    end
    try
        opType = ZOSAPI.Editors.MFE.MeritOperandType.(typeName);
        op = sys.MFE.AddOperand();
        op.ChangeType(opType);
        if ~isempty(target)
            op.Target = double(target);
        end
        op.Weight = double(weight);
    catch
    end
end
