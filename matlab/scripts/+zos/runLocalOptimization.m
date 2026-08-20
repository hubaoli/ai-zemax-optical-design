function result = runLocalOptimization(sys, varargin)
%RUNLOCALOPTIMIZATION Damped least squares, Automatic cycles. Returns merit struct.
    defaults = struct('seconds', [], 'cores', 8);
    opts = zos.parseNameValue(defaults, varargin{:});
    result = struct('initial', [], 'final', [], 'status', 'skipped');
    t0 = tic;
    tool = [];
    try
        tool = sys.Tools.OpenLocalOptimization();
        if isempty(tool)
            result.status = 'unavailable';
            return
        end
        try
            tool.Algorithm = ZOSAPI.Tools.Optimization.OptimizationAlgorithm.DampedLeastSquares;
        catch
        end
        try
            tool.Cycles = ZOSAPI.Tools.Optimization.OptimizationCycles.Automatic;
        catch
        end
        try
            tool.NumberOfCores = int32(opts.cores);
        catch
        end
        try
            result.initial = double(tool.InitialMeritFunction);
        catch
        end
        tool.RunAndWaitForCompletion();
        try
            result.final = double(tool.CurrentMeritFunction);
        catch
        end
        result.status = 'completed';
        result.elapsed_s = toc(t0);
        if ~isempty(opts.seconds) && result.elapsed_s > double(opts.seconds)
            result.status = 'completed_over_soft_timeout';
        end
    catch err
        result.status = ['error: ' err.message];
        result.elapsed_s = toc(t0);
    end
    zos.safeClose(tool);
end
