function profile = normalizeLensProfile(profile)
%NORMALIZELENSPROFILE Validate and enrich a zoom lens profile struct.
    if ~isstruct(profile)
        error('zos:Profile', 'Lens profile must be a struct.');
    end
    surfacesIn = zos.localGet(profile, 'surfaces', []);
    nSurfIn = zos.countItems(surfacesIn);
    if nSurfIn < 1
        error('zos:Profile', 'Lens profile must include a non-empty ''surfaces'' list.');
    end

    seen = [];
    surfaces = struct('surface', {}, 'radius', {}, 'thickness', {}, ...
        'material', {}, 'stop', {}, 'variable_gap', {}, 'group', {});
    for i = 1:nSurfIn
        raw = zos.getItem(surfacesIn, i);
        if ~isfield(raw, 'surface')
            error('zos:Profile', 'Each profile surface must include a ''surface'' index.');
        end
        idx = double(raw.surface);
        if any(seen == idx)
            error('zos:Profile', 'Duplicate surface index in lens profile: %g', idx);
        end
        seen(end + 1) = idx; %#ok<AGROW>
        rec = struct();
        rec.surface = idx;
        rec.radius = zos.profileNumber(zos.localGet(raw, 'radius', 'infinity'));
        rec.thickness = zos.profileNumber(zos.localGet(raw, 'thickness', 0));
        rec.material = char(zos.localGet(raw, 'material', ''));
        rec.stop = logical(zos.localGet(raw, 'stop', false));
        rec.variable_gap = char(zos.localGet(raw, 'variable_gap', ''));
        rec.group = char(zos.localGet(raw, 'group', ''));
        surfaces(end + 1) = rec; %#ok<AGROW>
    end
    [~, order] = sort([surfaces.surface]);
    surfaces = surfaces(order);

    gapsByName = struct();
    explicit = zos.localGet(profile, 'variable_gaps', []);
    for i = 1:zos.countItems(explicit)
        raw = zos.getItem(explicit, i);
        name = char(zos.localGet(raw, 'name', zos.localGet(raw, 'variable_gap', '')));
        if isempty(name)
            name = sprintf('gap_%g', zos.localGet(raw, 'surface', i));
        end
        if ~isfield(raw, 'surface')
            error('zos:Profile', 'Variable gap ''%s'' must include a surface index.', name);
        end
        g = struct();
        g.name = name;
        g.surface = double(raw.surface);
        g.default_mm = double(zos.localGet(raw, 'default_mm', zos.localGet(raw, 'default', 0)));
        g.per_config = zos.localGet(raw, 'per_config', struct());
        gapsByName.(matlab.lang.makeValidName(name)) = g;
        gapsByName.(matlab.lang.makeValidName(name)).name = name; %#ok<STRNU>
    end

    % Keep original names in a cell list as well
    variableGaps = struct('name', {}, 'surface', {}, 'default_mm', {}, 'per_config', {});
    names = fieldnames(gapsByName);
    for i = 1:numel(names)
        variableGaps(end + 1) = gapsByName.(names{i}); %#ok<AGROW>
    end

    for i = 1:numel(surfaces)
        gapName = surfaces(i).variable_gap;
        if isempty(gapName)
            continue
        end
        found = false;
        for j = 1:numel(variableGaps)
            if strcmp(variableGaps(j).name, gapName)
                found = true;
                break
            end
        end
        if ~found
            g = struct('name', gapName, 'surface', surfaces(i).surface, ...
                'default_mm', surfaces(i).thickness, 'per_config', struct());
            variableGaps(end + 1) = g; %#ok<AGROW>
        end
    end
    if ~isempty(variableGaps)
        [~, order] = sort([variableGaps.surface]);
        variableGaps = variableGaps(order);
    end

    imageSurface = double(zos.localGet(profile, 'image_surface', max([surfaces.surface])));
    surfaceCount = max([surfaces.surface]) + 1;
    merit = zos.localGet(profile, 'merit', struct());
    if ~isstruct(merit) || isempty(merit)
        merit = struct();
    end
    if ~isfield(merit, 'bfl_surface') || isempty(merit.bfl_surface)
        merit.bfl_surface = max(1, imageSurface - 1);
    end
    if ~isfield(merit, 'max_field_index') || isempty(merit.max_field_index)
        merit.max_field_index = 3;
    end
    mce = zos.localGet(profile, 'mce', struct());
    if ~isstruct(mce) || isempty(mce)
        mce = struct();
    end
    if ~isfield(mce, 'include_aperture_operand') || isempty(mce.include_aperture_operand)
        mce.include_aperture_operand = true;
    end
    if ~isfield(mce, 'include_field_operand') || isempty(mce.include_field_operand)
        mce.include_field_operand = true;
    end

    profile.surfaces = surfaces;
    profile.variable_gaps = variableGaps;
    profile.variable_gap_surfaces = [];
    if ~isempty(variableGaps)
        profile.variable_gap_surfaces = [variableGaps.surface];
    end
    profile.surface_count = surfaceCount;
    profile.image_surface = imageSurface;
    profile.merit = merit;
    profile.mce = mce;
    if ~isfield(profile, 'name') || isempty(profile.name)
        profile.name = 'unnamed zoom lens profile';
    end
    if ~isfield(profile, 'variables') || isempty(profile.variables)
        profile.variables = struct();
    end
end
