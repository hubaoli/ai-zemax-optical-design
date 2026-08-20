function setWavelengths(sys, wavelengths)
%SETWAVELENGTHS Replace System Explorer wavelengths from requirements.wavelengths_um.
    if nargin < 2 || zos.countItems(wavelengths) < 1
        wavelengths = [ ...
            struct('value', 0.486, 'weight', 1), ...
            struct('value', 0.588, 'weight', 1), ...
            struct('value', 0.656, 'weight', 1)];
    end
    editor = sys.SystemData.Wavelengths;
    while editor.NumberOfWavelengths > 1
        editor.RemoveWavelength(int32(editor.NumberOfWavelengths));
    end
    first = zos.getItem(wavelengths, 1);
    editor.GetWavelength(int32(1)).Wavelength = double(zos.localGet(first, 'value', 0.588));
    editor.GetWavelength(int32(1)).Weight = double(zos.localGet(first, 'weight', 1));
    n = zos.countItems(wavelengths);
    for i = 2:n
        item = zos.getItem(wavelengths, i);
        editor.AddWavelength(double(zos.localGet(item, 'value', 0.588)), ...
            double(zos.localGet(item, 'weight', 1)));
    end
end
