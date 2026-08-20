function configureZoomVariables(sys, profile, stage)
%CONFIGUREZOOMVARIABLES Surgical variable release from profile.variables.
    if strcmp(stage, 'baseline')
        return
    end
    lde = sys.LDE;
    mce = sys.MCE;
    vars = zos.localGet(profile, 'variables', struct());
    nSurf = double(lde.NumberOfSurfaces);

    try
        sys.Tools.RemoveAllVariables();
    catch
    end

    mceTypes = zos.localGet(vars, 'mce_variable_operand_types', []);
    allowThic = true;
    if zos.countItems(mceTypes) > 0
        allowThic = false;
        for i = 1:zos.countItems(mceTypes)
            if strcmpi(char(zos.getItem(mceTypes, i)), 'THIC')
                allowThic = true;
            end
        end
    end
    if allowThic
        for opIdx = 1:double(mce.NumberOfOperands)
            try
                operand = mce.GetOperandAt(int32(opIdx));
                typeName = '';
                try
                    typeName = char(operand.TypeName);
                catch
                end
                if ~isempty(typeName) && ~strcmpi(typeName, 'THIC')
                    continue
                end
                for cfg = 1:double(mce.NumberOfConfigurations)
                    try
                        operand.GetOperandCell(int32(cfg)).MakeSolveVariable();
                    catch
                    end
                end
            catch
            end
        end
    end

    switch stage
        case 'feasibility'
            radii = listOr(vars, 'feasibility_radius_surfaces', poweredSurfaces(profile, nSurf));
            varyRadii(lde, radii, true);
            try
                bfl = double(zos.localGet(profile, 'merit.bfl_surface', max(1, nSurf - 2)));
                lde.GetSurfaceAt(int32(bfl)).ThicknessCell.MakeSolveVariable();
            catch
            end
        case {'image-quality', 'field-balance'}
            radii = listOr(vars, [stage '_radius_surfaces'], interiorSurfaces(profile, nSurf));
            thick = listOr(vars, [stage '_thickness_surfaces'], interiorSurfaces(profile, nSurf));
            varyRadii(lde, radii, false);
            varyThick(lde, thick);
        case 'manufacturability'
            radii = listOr(vars, 'manufacturability_radius_surfaces', interiorSurfaces(profile, nSurf));
            thick = listOr(vars, 'manufacturability_thickness_surfaces', interiorSurfaces(profile, nSurf));
            mats = listOr(vars, 'material_surfaces', glassSurfaces(profile));
            varyRadii(lde, radii, false);
            varyThick(lde, thick);
            for i = 1:numel(mats)
                try
                    s = lde.GetSurfaceAt(int32(mats(i)));
                    if ~isempty(char(s.Material))
                        s.MaterialCell.MakeSolveVariable();
                    end
                catch
                end
            end
    end
    fprintf('  Variables configured for stage: %s\n', stage);
end

function vals = listOr(vars, field, fallback)
    raw = zos.localGet(vars, matlab.lang.makeValidName(field), []);
    if isempty(raw)
        raw = zos.localGet(vars, field, []);
    end
    if isempty(raw)
        vals = fallback;
    else
        vals = double(raw(:).');
    end
end

function varyRadii(lde, idxs, glassOnly)
    for i = 1:numel(idxs)
        try
            s = lde.GetSurfaceAt(int32(idxs(i)));
            if glassOnly
                mat = '';
                try
                    mat = char(s.Material);
                catch
                end
                if isempty(mat)
                    continue
                end
            end
            s.RadiusCell.MakeSolveVariable();
        catch
        end
    end
end

function varyThick(lde, idxs)
    for i = 1:numel(idxs)
        try
            lde.GetSurfaceAt(int32(idxs(i))).ThicknessCell.MakeSolveVariable();
        catch
        end
    end
end

function idx = interiorSurfaces(profile, nSurf)
    imageSurface = double(zos.localGet(profile, 'image_surface', max(1, nSurf - 1)));
    idx = [];
    n = zos.countItems(profile.surfaces);
    for i = 1:n
        s = zos.getItem(profile.surfaces, i);
        if s.surface > 0 && s.surface < imageSurface
            idx(end + 1) = s.surface; %#ok<AGROW>
        end
    end
end

function idx = glassSurfaces(profile)
    idx = [];
    n = zos.countItems(profile.surfaces);
    for i = 1:n
        s = zos.getItem(profile.surfaces, i);
        if ~isempty(s.material)
            idx(end + 1) = s.surface; %#ok<AGROW>
        end
    end
end

function idx = poweredSurfaces(profile, nSurf)
    idx = [];
    imageSurface = double(zos.localGet(profile, 'image_surface', nSurf - 1));
    n = zos.countItems(profile.surfaces);
    for i = 1:n
        s = zos.getItem(profile.surfaces, i);
        if s.surface > 0 && s.surface < imageSurface && isfinite(s.radius)
            idx(end + 1) = s.surface; %#ok<AGROW>
        end
    end
    if isempty(idx)
        idx = interiorSurfaces(profile, nSurf);
    end
end
