function value = meritValue(sys)
%MERITVALUE Current merit function value via MeritFunctionCalculator, else MFE.
    value = [];
    calc = [];
    try
        calc = sys.Tools.OpenMeritFunctionCalculator();
        calc.RunAndWaitForCompletion();
        try
            value = double(calc.MeritFunctionCalculation);
        catch
            value = double(calc.MeritFunction);
        end
    catch
    end
    zos.safeClose(calc);
    if isempty(value)
        try
            value = double(sys.MFE.CalculateMeritFunction());
        catch
            try
                sys.MFE.CalculateMeritFunction();
                value = double(sys.MFE.GetOperandAt(int32(1)).Value);
            catch
            end
        end
    end
end
