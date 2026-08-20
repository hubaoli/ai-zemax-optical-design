function value = resolveGapInitialValue(gap, zoomConfig)
%RESOLVEGAPINITIALVALUE Priority: gap_values_mm name → per_config name match → default_mm.
    explicit = zos.localGet(zoomConfig, 'gap_values_mm', []);
    if isempty(explicit)
        explicit = zos.localGet(zoomConfig, 'gaps_mm', struct());
    end
    gapName = char(zos.localGet(gap, 'name', ''));
    if isstruct(explicit)
        if ~isempty(gapName) && isfield(explicit, gapName)
            value = double(explicit.(gapName));
            return
        end
        surfKey = sprintf('%g', zos.localGet(gap, 'surface', []));
        if isfield(explicit, surfKey)
            value = double(explicit.(surfKey));
            return
        end
    end

    cfgName = lower(char(zos.localGet(zoomConfig, 'name', '')));
    per = zos.localGet(gap, 'per_config', struct());
    if isstruct(per) && ~isempty(fieldnames(per))
        keys = fieldnames(per);
        for i = 1:numel(keys)
            k = lower(keys{i});
            if strcmp(k, cfgName) || contains(cfgName, k)
                value = double(per.(keys{i}));
                return
            end
        end
    end
    value = double(zos.localGet(gap, 'default_mm', 0));
end
