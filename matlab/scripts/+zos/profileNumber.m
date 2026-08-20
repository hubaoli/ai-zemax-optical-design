function n = profileNumber(value)
%PROFILENUMBER Convert JSON radius/thickness (number or "infinity") to double.
    if ischar(value) || isstring(value)
        s = lower(strtrim(char(value)));
        if any(strcmp(s, {'inf', '+inf', 'infinity', '+infinity'}))
            n = inf;
            return
        end
        if any(strcmp(s, {'-inf', '-infinity'}))
            n = -inf;
            return
        end
        n = str2double(s);
        return
    end
    n = double(value);
end
