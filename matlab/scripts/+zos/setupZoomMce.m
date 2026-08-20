function setupZoomMce(sys, zoomConfigs, profile)
%SETUPZOOMMCE THIC per variable gap, optional APER and YFIE. Enum types only.
    mce = sys.MCE;
    nCfg = zos.countItems(zoomConfigs);
    if nCfg < 1
        error('zos:MCE', 'No zoom configurations in requirements.');
    end

    includeAper = logical(zos.localGet(profile, 'mce.include_aperture_operand', true));
    includeField = logical(zos.localGet(profile, 'mce.include_field_operand', true));
    gaps = profile.variable_gaps;
    nGaps = zos.countItems(gaps);

    while mce.NumberOfConfigurations < nCfg
        mce.AddConfiguration(true);
    end
    while mce.NumberOfConfigurations > nCfg
        mce.DeleteConfiguration(int32(mce.NumberOfConfigurations));
    end

    needed = nGaps + double(includeAper) + double(includeField);
    while mce.NumberOfOperands < needed
        mce.AddOperand();
    end
    while mce.NumberOfOperands > needed
        try
            mce.RemoveOperandAt(int32(mce.NumberOfOperands));
        catch
            break
        end
    end

    THIC = ZOSAPI.Editors.MCE.MultiConfigOperandType.THIC;
    for i = 1:nGaps
        gap = zos.getItem(gaps, i);
        op = mce.GetOperandAt(int32(i));
        op.ChangeType(THIC);
        op.Param1 = int32(gap.surface);
        for c = 1:nCfg
            cfg = zos.getItem(zoomConfigs, c);
            gapVal = zos.resolveGapInitialValue(gap, cfg);
            op.GetOperandCell(int32(c)).DoubleValue = gapVal;
            fprintf('    THIC %s S%g Config%g=''%s'': %gmm\n', ...
                gap.name, gap.surface, c, char(zos.localGet(cfg, 'name', '')), gapVal);
        end
    end

    opIdx = nGaps;
    if includeAper
        opIdx = opIdx + 1;
        op = mce.GetOperandAt(int32(opIdx));
        op.ChangeType(ZOSAPI.Editors.MCE.MultiConfigOperandType.APER);
        try
            op.Param1 = int32(0);
        catch
        end
        defaultF = double(zos.localGet(profile, 'mce.default_f_number', 1.4));
        for c = 1:nCfg
            cfg = zos.getItem(zoomConfigs, c);
            fnum = double(zos.localGet(cfg, 'f_number', defaultF));
            op.GetOperandCell(int32(c)).DoubleValue = fnum;
            fprintf('    APER Config%g: F/%g\n', c, fnum);
        end
    end

    if includeField
        opIdx = opIdx + 1;
        op = mce.GetOperandAt(int32(opIdx));
        op.ChangeType(ZOSAPI.Editors.MCE.MultiConfigOperandType.YFIE);
        maxField = int32(zos.localGet(profile, 'merit.max_field_index', 3));
        try
            op.Param1 = maxField;
        catch
        end
        defaultH = double(zos.localGet(profile, 'mce.default_image_height_mm', 14.17));
        for c = 1:nCfg
            cfg = zos.getItem(zoomConfigs, c);
            imgH = double(zos.localGet(cfg, 'image_height_mm', defaultH));
            op.GetOperandCell(int32(c)).DoubleValue = imgH;
            fprintf('    YFIE Config%g: %gmm image height\n', c, imgH);
        end
    end

    fprintf('  MCE: %g configs, %g operands\n', ...
        double(mce.NumberOfConfigurations), double(mce.NumberOfOperands));
end
