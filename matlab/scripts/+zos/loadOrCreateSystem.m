function [sys, seedContext] = loadOrCreateSystem(app, req)
%LOADORCREATESYSTEM Load input_lens / seed path, else build a conservative starter.
    sys = app.PrimarySystem;
    seedContext = buildSeedContext(req);
    [seedPath, seedContext] = resolveSeedPath(req, seedContext);
    if ~isempty(seedPath)
        if exist(seedPath, 'file') == 2
            try
                sys.LoadFile(seedPath, false);
                seedContext.selection.loaded = true;
                seedContext.selection.exists = true;
                return
            catch err
                seedContext.selection.loaded = false;
                seedContext.selection.load_error = err.message;
            end
        else
            seedContext.selection.exists = false;
            seedContext.selection.loaded = false;
        end
    end
    seedContext = createSeededSequentialSystem(sys, req, seedContext);
end

function ctx = buildSeedContext(req)
    seed = zos.localGet(req, 'seed_design', struct());
    if isempty(seed)
        seed = struct();
    end
    ctx = struct();
    ctx.seed_design = struct();
    ctx.seed_design.preferred_source = zos.localGet(seed, 'preferred_source', '');
    ctx.seed_design.family_hint = zos.localGet(seed, 'family_hint', '');
    ctx.seed_design.match_axes = zos.localGet(seed, 'match_axes', {});
    ctx.seed_design.provenance = zos.localGet(seed, 'provenance', struct());
    ctx.seed_design.structural_gaps = zos.localGet(seed, 'structural_gaps', {});
    ctx.seed_design.selected_case = zos.localGet(seed, 'selected_case', '');
    ctx.seed_design.selected_case_path = zos.localGet(seed, 'selected_case_path', '');
    ctx.seed_design.selection_notes = zos.localGet(seed, 'selection_notes', {});
    ctx.selection = struct();
    ctx.starter_profile = struct();
end

function [seedPath, seedContext] = resolveSeedPath(req, seedContext)
    seedPath = '';
    candidates = { ...
        zos.localGet(req, 'input_lens', ''), 'input_lens'; ...
        zos.localGet(seedContext.seed_design, 'selected_case_path', ''), 'seed_design.selected_case_path'; ...
        zos.localGet(zos.localGet(seedContext.seed_design, 'provenance', struct()), 'source_path', ''), 'seed_design.provenance.source_path'};
    base = fileparts(zos.localGet(req, 'source_path', ''));
    for i = 1:size(candidates, 1)
        cand = candidates{i, 1};
        if isempty(cand)
            continue
        end
        p = char(cand);
        if ~isempty(base) && isempty(regexp(p, '^[A-Za-z]:[\\/]', 'once'))
            p = fullfile(base, p);
        end
        p = zos.absPath(p);
        seedContext.selection.selected_case = seedContext.seed_design.selected_case;
        if isempty(seedContext.selection.selected_case)
            [~, stem] = fileparts(p);
            seedContext.selection.selected_case = stem;
        end
        seedContext.selection.selected_case_path = p;
        seedContext.selection.source_label = candidates{i, 2};
        seedContext.selection.source = 'explicit_path';
        seedPath = p;
        return
    end
end

function seedContext = createSeededSequentialSystem(sys, req, seedContext)
    sys.New(false);
    zos.setWavelengths(sys, zos.localGet(req, 'wavelengths_um', []));
    zos.setFields(sys, zos.localGet(req, 'fields', []));
    zos.setAperture(sys, zos.localGet(req, 'aperture', struct()));

    lde = sys.LDE;
    family = lower(char(zos.localGet(seedContext.seed_design, 'family_hint', '')));
    gaps = zos.localGet(seedContext.seed_design, 'structural_gaps', {});
    maxElem = zos.localGet(req, 'constraints.max_elements', []);

    starter = 4;
    if contains(family, 'zoom') || hasGapAxis(gaps, 'group_count')
        starter = 8;
    end
    if zos.countItems(gaps) > 0
        starter = max(starter, 6);
    end
    if ~isempty(maxElem) && isnumeric(maxElem)
        starter = min(starter, max(4, double(maxElem) + 2));
    end

    while lde.NumberOfSurfaces < starter
        lde.InsertNewSurfaceAt(int32(max(1, lde.NumberOfSurfaces)));
    end

    powered = starterPowered(double(lde.NumberOfSurfaces), family, gaps);
    populateStarter(lde, powered, family);
    seedContext.starter_profile = struct( ...
        'family_hint', zos.localGet(seedContext.seed_design, 'family_hint', ''), ...
        'surface_count', double(lde.NumberOfSurfaces), ...
        'powered_surfaces', powered, ...
        'starter_profile', 'seed-aware');
end

function tf = hasGapAxis(gaps, axis)
    tf = false;
    n = zos.countItems(gaps);
    for i = 1:n
        g = zos.getItem(gaps, i);
        if strcmp(char(zos.localGet(g, 'axis', '')), axis)
            tf = true;
            return
        end
    end
end

function powered = starterPowered(nSurf, family, gaps)
    if nSurf <= 4
        powered = [1, 2];
        return
    end
    if contains(family, 'zoom')
        powered = [1, 2, max(2, floor(nSurf / 2) - 1), max(3, floor(nSurf / 2)), nSurf - 2];
        return
    end
    critical = false;
    n = zos.countItems(gaps);
    for i = 1:n
        g = zos.getItem(gaps, i);
        if strcmp(char(zos.localGet(g, 'severity', '')), 'critical')
            critical = true;
        end
    end
    if critical
        powered = [1, 2, nSurf - 2];
    else
        powered = [1, 2, nSurf - 2];
    end
end

function populateStarter(lde, powered, family)
    for i = 1:numel(powered)
        idx = powered(i);
        try
            s = lde.GetSurfaceAt(int32(idx));
        catch
            continue
        end
        if i == 1
            s.Radius = 60.0;
            s.Thickness = 6.0;
            s.Material = 'N-BK7';
        elseif i == numel(powered)
            s.Radius = -60.0;
            s.Thickness = 40.0;
            s.Material = '';
        else
            if contains(family, 'zoom')
                s.Radius = 90.0;
                s.Material = 'N-LAK22';
            else
                s.Radius = 120.0;
                s.Material = '';
            end
            s.Thickness = 8.0;
        end
    end
end
