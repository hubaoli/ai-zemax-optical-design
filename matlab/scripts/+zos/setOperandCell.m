function setOperandCell(op, col, value)
%SETOPERANDCELL Set an MFE/MCE operand cell, trying GetOperandCell then GetCellAt.
    col = int32(col);
    cell = [];
    try
        cell = op.GetOperandCell(col);
    catch
        try
            cell = op.GetCellAt(col);
        catch
            return
        end
    end
    if isempty(cell)
        return
    end
    try
        if isnumeric(value) && isfinite(value) && abs(value - round(value)) < 1e-9 && abs(value) < 1e7
            try
                cell.IntegerValue = int32(value);
                return
            catch
            end
        end
        cell.DoubleValue = double(value);
    catch
    end
end
