function testZoomLensProfile()
%TESTZOOMLENSPROFILE No OpticStudio required. Validates profile JSON + gap priority.
    thisDir = fileparts(mfilename('fullpath'));
    scriptsDir = fullfile(thisDir, '..', 'scripts');
    repoRoot = fullfile(thisDir, '..', '..');
    addpath(scriptsDir, '-begin');

    profilePath = fullfile(repoRoot, 'examples', 'profiles', 'apsc_18_55_f14_zoom_profile.json');
    reqPath = fullfile(repoRoot, 'examples', 'apsc_18-55_f1.4_zoom_requirements.json');
    assert(exist(profilePath, 'file') == 2, 'Missing example profile.');
    assert(exist(reqPath, 'file') == 2, 'Missing example zoom requirements.');

    raw = jsondecode(fileread(profilePath));
    profile = zos.normalizeLensProfile(raw);
    assert(profile.image_surface == 24);
    assert(profile.surface_count == 25);
    assert(zos.countItems(profile.variable_gaps) == 3);
    names = {profile.variable_gaps.name};
    assert(any(strcmp(names, 'front_to_variator')));
    assert(any(strcmp(names, 'variator_to_compensator')));
    assert(any(strcmp(names, 'compensator_to_relay')));

    req = zos.loadRequirements(reqPath);
    loaded = zos.loadLensProfile(req, fileparts(reqPath));
    assert(zos.countItems(loaded.surfaces) >= 20, 'Profile surfaces not loaded from requirements.lens_profile.');

    cfgs = zos.localGet(req, 'constraints.zoom_configurations', []);
    assert(zos.countItems(cfgs) == 3);

    gap1 = [];
    for i = 1:zos.countItems(profile.variable_gaps)
        g = zos.getItem(profile.variable_gaps, i);
        if strcmp(g.name, 'front_to_variator')
            gap1 = g;
        end
    end
    assert(~isempty(gap1));

    wide = zos.getItem(cfgs, 1);
    mid = zos.getItem(cfgs, 2);
    tele = zos.getItem(cfgs, 3);
    assert(abs(zos.resolveGapInitialValue(gap1, wide) - 4.0) < 1e-9);
    assert(abs(zos.resolveGapInitialValue(gap1, mid) - 22.0) < 1e-9);
    assert(abs(zos.resolveGapInitialValue(gap1, tele) - 35.0) < 1e-9);

    % Explicit gap_values_mm wins over per_config
    wide.gap_values_mm = struct('front_to_variator', 9.5);
    assert(abs(zos.resolveGapInitialValue(gap1, wide) - 9.5) < 1e-9);

    % jsondecode hyphenated variable keys remain readable via localGet
    radii = zos.localGet(profile, 'variables.image-quality_radius_surfaces', []);
    assert(zos.countItems(radii) > 0, 'image-quality_radius_surfaces not readable (jsondecode name mangling).');

    fprintf('testZoomLensProfile: PASS\n');
    fprintf('  profile=%s surfaces=%g gaps=%g IQ-radii=%g\n', ...
        char(profile.name), zos.countItems(profile.surfaces), ...
        zos.countItems(profile.variable_gaps), zos.countItems(radii));
end
