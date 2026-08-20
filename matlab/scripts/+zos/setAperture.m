function setAperture(sys, aperture)
%SETAPERTURE Set System Explorer aperture from requirements.aperture.
    if nargin < 2 || isempty(aperture)
        aperture = struct('type', 'f_number', 'value', 4.0);
    end
    value = double(zos.localGet(aperture, 'value', 4.0));
    typ = lower(char(zos.localGet(aperture, 'type', 'f_number')));
    ap = sys.SystemData.Aperture;
    try
        switch typ
            case {'f_number', 'image_f_number', 'fnumber'}
                ap.ApertureType = ZOSAPI.SystemData.ZemaxApertureType.ImageFNumber;
            case {'epd_mm', 'entrance_pupil_diameter', 'epd'}
                ap.ApertureType = ZOSAPI.SystemData.ZemaxApertureType.EntrancePupilDiameter;
            case {'float_by_stop', 'float_by_stop_size'}
                ap.ApertureType = ZOSAPI.SystemData.ZemaxApertureType.FloatByStopSize;
            otherwise
                % keep current type; still set value
        end
    catch
    end
    try
        ap.ApertureValue = value;
    catch
    end
end
