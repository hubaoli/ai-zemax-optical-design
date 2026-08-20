function exported = exportZoomAnalyses(sys, analysisDir, zoomConfigs)
%EXPORTZOOMANALYSES Per-configuration analysis text exports.
    analysisDir = zos.ensureDir(analysisDir);
    factories = { ...
        'spot', 'New_StandardSpot'; ...
        'mtf', 'New_FftMtf'; ...
        'wavefront', 'New_WavefrontMap'; ...
        'rayfan', 'New_RayFan'; ...
        'distortion', 'New_FieldCurvatureAndDistortion'};
    exported = {};
    mce = sys.MCE;
    nCfg = zos.countItems(zoomConfigs);
    for c = 1:nCfg
        cfg = zos.getItem(zoomConfigs, c);
        cfgName = char(zos.localGet(cfg, 'name', sprintf('config_%d', c)));
        try
            mce.SetCurrentConfiguration(int32(c));
        catch
            try
                mce.CurrentConfiguration = int32(c);
            catch
            end
        end
        for i = 1:size(factories, 1)
            name = factories{i, 1};
            factory = factories{i, 2};
            analysis = [];
            try
                analysis = sys.Analyses.(factory)();
                analysis.ApplyAndWaitForCompletion();
                out = fullfile(analysisDir, sprintf('%s_%s.txt', name, cfgName));
                analysis.GetResults().GetTextFile(out);
                exported{end + 1} = out; %#ok<AGROW>
            catch err
                warning('zos:Analysis', '%s@%s: %s', name, cfgName, err.message);
            end
            zos.safeClose(analysis);
        end
    end
end
