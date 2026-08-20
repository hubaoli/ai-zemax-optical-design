function setCurrentConfiguration(sys, cfg)
%SETCURRENTCONFIGURATION Switch MCE configuration (1-based).
    mce = sys.MCE;
    cfg = int32(cfg);
    try
        mce.SetCurrentConfiguration(cfg);
    catch
        mce.CurrentConfiguration = cfg;
    end
end
