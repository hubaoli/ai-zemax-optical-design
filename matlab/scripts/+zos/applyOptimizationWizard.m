function ok = applyOptimizationWizard(sys, varargin)
%APPLYOPTIMIZATIONWIZARD RMS-spot SEQ wizard. Tries Apply() then OK().
    defaults = struct( ...
        'data', 1, ...
        'ring', 2, ...
        'arm', 0, ...
        'glassMin', 1.5, ...
        'glassMax', 15.0, ...
        'glassEdge', 2.0, ...
        'airMin', 0.5, ...
        'airMax', 1000.0, ...
        'airEdge', 0.5, ...
        'useGlass', true, ...
        'useAir', true);
    opts = zos.parseNameValue(defaults, varargin{:});
    ok = false;
    try
        wiz = sys.MFE.SEQOptimizationWizard;
    catch
        return
    end
    setProp(wiz, 'Data', opts.data);
    setProp(wiz, 'Ring', opts.ring);
    setProp(wiz, 'Arm', opts.arm);
    setProp(wiz, 'OverallWeight', 1.0);
    setProp(wiz, 'IsGlassUsed', opts.useGlass);
    setProp(wiz, 'IsAirUsed', opts.useAir);
    setProp(wiz, 'GlassMin', opts.glassMin);
    setProp(wiz, 'GlassMax', opts.glassMax);
    setProp(wiz, 'GlassEdge', opts.glassEdge);
    setProp(wiz, 'AirMin', opts.airMin);
    setProp(wiz, 'AirMax', opts.airMax);
    setProp(wiz, 'AirEdge', opts.airEdge);
    try
        wiz.Apply();
        ok = true;
        return
    catch
    end
    try
        wiz.OK();
        ok = true;
    catch
    end
end

function setProp(obj, name, value)
    try
        obj.(name) = value;
    catch
    end
end
