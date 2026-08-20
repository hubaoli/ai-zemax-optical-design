function metrics = parseMetrics(analysisFiles)
%PARSEMETRICS Parse Zemax analysis text into stable metric keys.
    metrics = struct();
    metrics.analysis_files = analysisFiles;
    metrics.parser_notes = {};
    metrics.summary = struct( ...
        'merit_value', [], ...
        'efl_mm', [], ...
        'bfl_mm', [], ...
        'total_track_mm', [], ...
        'f_number', [], ...
        'na', [], ...
        'rms_spot_um', [], ...
        'mtf', struct(), ...
        'distortion_percent', [], ...
        'wavefront_rms_waves', [], ...
        'constraint_violations', 0);

    if ischar(analysisFiles)
        analysisFiles = {analysisFiles};
    end
    for i = 1:numel(analysisFiles)
        f = analysisFiles{i};
        txt = zos.readTextRobust(f);
        parsed = parseOne(txt);
        note = struct('file', f, 'chars', numel(txt), 'signals', {fieldnames(parsed)});
        metrics.parser_notes{end + 1} = note; %#ok<AGROW>
        metrics.summary = mergeSummary(metrics.summary, parsed);
    end
end

function parsed = parseOne(txt)
    parsed = struct();
    parsed = take(parsed, txt, 'merit_value', '(?:merit(?: function)?(?: value)?)');
    parsed = take(parsed, txt, 'rms_spot_um', '(?:rms\s+spot)');
    parsed = take(parsed, txt, 'distortion_percent', '(?:distortion)');
    parsed = take(parsed, txt, 'wavefront_rms_waves', '(?:wavefront(?:\s+rms)?)');
    parsed = take(parsed, txt, 'efl_mm', '(?:efl)');
    parsed = take(parsed, txt, 'bfl_mm', '(?:bfl)');
    parsed = take(parsed, txt, 'total_track_mm', '(?:total\s+track)');
    parsed = take(parsed, txt, 'f_number', '(?:f/#|f-number|f number)');
    parsed = take(parsed, txt, 'na', '(?:na|numerical aperture)');

    mtfTok = regexp(txt, 'mtf\s*([0-9]+(?:\.\d+)?)\s*lp/mm[^0-9+-]*([-+]?\d+(?:\.\d+)?)', ...
        'tokens', 'ignorecase');
    if ~isempty(mtfTok)
        mtf = struct();
        for i = 1:numel(mtfTok)
            freq = mtfTok{i}{1};
            key = ['f' regexprep(freq, '\.', '_')];
            mtf.(key) = str2double(mtfTok{i}{2});
        end
        parsed.mtf = mtf;
    end
    if ~isempty(regexpi(txt, '\bviolation\b', 'once'))
        parsed.constraint_violations = 1;
    end
end

function parsed = take(parsed, txt, key, pattern)
    tok = regexp(txt, ['(?<=^|\n)' pattern '[^0-9+-]*([-+]?\d+(?:\.\d+)?)'], ...
        'tokens', 'once', 'ignorecase');
    if isempty(tok)
        tok = regexp(txt, [pattern '[^0-9+-]*([-+]?\d+(?:\.\d+)?)'], ...
            'tokens', 'once', 'ignorecase');
    end
    if ~isempty(tok)
        parsed.(key) = str2double(tok{1});
    end
end

function summary = mergeSummary(summary, parsed)
    keys = {'merit_value', 'efl_mm', 'bfl_mm', 'total_track_mm', 'f_number', ...
        'na', 'rms_spot_um', 'distortion_percent', 'wavefront_rms_waves'};
    for i = 1:numel(keys)
        k = keys{i};
        if isfield(parsed, k)
            summary.(k) = parsed.(k);
        end
    end
    if isfield(parsed, 'constraint_violations')
        summary.constraint_violations = summary.constraint_violations + parsed.constraint_violations;
    end
    if isfield(parsed, 'mtf')
        fn = fieldnames(parsed.mtf);
        for i = 1:numel(fn)
            summary.mtf.(fn{i}) = parsed.mtf.(fn{i});
        end
    end
end
