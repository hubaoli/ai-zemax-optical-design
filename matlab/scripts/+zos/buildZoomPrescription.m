function gapSurfaces = buildZoomPrescription(sys, profile)
%BUILDZOOMPRESCRIPTION Sequential LDE from a normalized zoom profile.
    lde = sys.LDE;
    nWanted = double(profile.surface_count);
    while lde.NumberOfSurfaces < nWanted
        lde.InsertNewSurfaceAt(int32(lde.NumberOfSurfaces));
    end
    while lde.NumberOfSurfaces > nWanted
        try
            lde.RemoveSurfacesAt(int32(lde.NumberOfSurfaces), int32(1));
        catch
            try
                lde.RemoveSurface(int32(lde.NumberOfSurfaces));
            catch
                break
            end
        end
    end

    n = zos.countItems(profile.surfaces);
    for i = 1:n
        rec = zos.getItem(profile.surfaces, i);
        idx = double(rec.surface);
        if idx < 1
            continue  % object surface 0: keep New() default
        end
        try
            s = lde.GetSurfaceAt(int32(idx));
        catch
            continue
        end
        r = rec.radius;
        t = rec.thickness;
        if isfinite(r)
            s.Radius = r;
        end
        if isfinite(t)
            s.Thickness = t;
        end
        s.Material = rec.material;
        if isfield(rec, 'stop') && rec.stop
            try
                sys.LDE.StopSurface = int32(idx);
            catch
            end
            try
                s.IsStop = true;
            catch
            end
        end
    end

    gapSurfaces = profile.variable_gap_surfaces;
    fprintf('  Prescription profile: %s\n', char(profile.name));
    fprintf('  Surfaces: %g, variable gaps: %s\n', profile.surface_count, mat2str(gapSurfaces));
end
