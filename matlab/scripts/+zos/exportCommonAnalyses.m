function exported = exportCommonAnalyses(sys, analysisDir)
%EXPORTCOMMONANALYSES Spot, FFT MTF, wavefront, ray fan, field curvature/distortion.
    analysisDir = zos.ensureDir(analysisDir);
    factories = { ...
        'spot', 'New_StandardSpot'; ...
        'mtf', 'New_FftMtf'; ...
        'wavefront', 'New_WavefrontMap'; ...
        'rayfan', 'New_RayFan'; ...
        'distortion', 'New_FieldCurvatureAndDistortion'};
    exported = {};
    for i = 1:size(factories, 1)
        name = factories{i, 1};
        factory = factories{i, 2};
        analysis = [];
        try
            analysis = sys.Analyses.(factory)();
            analysis.ApplyAndWaitForCompletion();
            out = fullfile(analysisDir, [name '.txt']);
            analysis.GetResults().GetTextFile(out);
            exported{end + 1} = out; %#ok<AGROW>
        catch err
            warning('zos:Analysis', '%s failed: %s', name, err.message);
        end
        zos.safeClose(analysis);
    end
end
