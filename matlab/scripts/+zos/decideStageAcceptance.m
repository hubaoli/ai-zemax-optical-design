function decision = decideStageAcceptance(prevMetrics, currMetrics, stage, req)
%DECIDESTAGEACCEPTANCE Compare summaries; reject constraint regressions.
    prev = struct();
    curr = struct();
    if isstruct(prevMetrics) && isfield(prevMetrics, 'summary')
        prev = prevMetrics.summary;
    end
    if isstruct(currMetrics) && isfield(currMetrics, 'summary')
        curr = currMetrics.summary;
    end

    reasons = {};
    prevV = getNum(prev, 'constraint_violations', 0);
    currV = getNum(curr, 'constraint_violations', 0);
    if currV > prevV
        reasons{end + 1} = 'constraint regression'; %#ok<AGROW>
    end

    score = 0;
    score = score + cmpLower(prev, curr, 'merit_value');
    score = score + cmpLower(prev, curr, 'rms_spot_um');
    score = score + cmpLower(prev, curr, 'distortion_percent');
    score = score + cmpLower(prev, curr, 'wavefront_rms_waves');
    score = score + cmpLower(prev, curr, 'total_track_mm');

    if strcmp(stage, 'baseline') || isempty(prevMetrics)
        accepted = true;
        recovery = 'accept';
        reasons{end + 1} = 'baseline accepted'; %#ok<AGROW>
    else
        accepted = (currV <= prevV) && (score > 0) && ~any(strcmp(reasons, 'constraint regression'));
        recovery = 'accept';
        if ~accepted
            recovery = 'shrink_variable_set';
        end
        if score > 0
            reasons{end + 1} = 'metrics improved'; %#ok<AGROW>
        elseif score < 0
            reasons{end + 1} = 'metrics regressed'; %#ok<AGROW>
        else
            reasons{end + 1} = 'metrics unchanged'; %#ok<AGROW>
        end
    end

    zoom = false;
    if strcmp(char(zos.localGet(req, 'seed_design.family_hint', '')), 'zoom_imaging')
        zoom = true;
    end
    if zos.countItems(zos.localGet(req, 'constraints.zoom_configurations', [])) > 0
        zoom = true;
    end
    if ~strcmp(stage, 'baseline') && zoom && ~accepted
        recovery = 'rollback_then_shrink';
    end

    decision = struct();
    decision.accepted = accepted;
    decision.score = score;
    decision.reason = strjoin(reasons, '; ');
    decision.recovery_action = recovery;
    decision.current_violations = currV;
    decision.previous_violations = prevV;
end

function v = getNum(s, key, default)
    v = default;
    if isstruct(s) && isfield(s, key) && ~isempty(s.(key))
        v = double(s.(key));
    end
end

function d = cmpLower(prev, curr, key)
    d = 0;
    a = getNum(prev, key, []);
    b = getNum(curr, key, []);
    if isempty(a) || isempty(b)
        return
    end
    if b < a
        d = 1;
    elseif b > a
        d = -1;
    end
end
