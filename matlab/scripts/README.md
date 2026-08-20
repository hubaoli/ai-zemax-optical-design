# MATLAB scripts

Add this folder to the MATLAB path (the `+zos` package lives here). Entry functions do `addpath` themselves.

Requires 64-bit MATLAB + 64-bit OpticStudio. Open OpticStudio and start **Programming → MATLAB → Interactive Extension** unless you pass `'mode','standalone'`.

```matlab
cd('.../ai-zemax-optical-design/matlab/scripts')

% 1. Connection
connectionSmokeTest
% connectionSmokeTest('mode', 'standalone', 'zosRoot', 'C:\Program Files\Ansys Zemax OpticStudio 2024 R1.00')

% 2. Prime / seed loop
automatedDesignAgent( ...
    'requirements', fullfile('..', '..', 'examples', 'minimal_imaging_requirements.json'), ...
    'out', fullfile('..', '..', 'output', 'my-design'))

% 3. Profile-driven zoom
zoomLensDesignAgent( ...
    'requirements', fullfile('..', '..', 'examples', 'apsc_18-55_f1.4_zoom_requirements.json'), ...
    'out', fullfile('..', '..', 'output', 'aps-c-zoom'))

% 4. Singlet fallback
designSingleLensStandalone('out', fullfile('..', '..', 'output', 'singlet'), 'eflMm', 50)

% Profile unit test (no OpticStudio)
run(fullfile('..', 'tests', 'testZoomLensProfile.m'))
```

Common name-value options: `'mode'`, `'instanceId'` (default 0), `'zosRoot'`, `'out'`.

Do **not** call `CloseApplication` after Interactive Extension. Standalone mode closes automatically.
