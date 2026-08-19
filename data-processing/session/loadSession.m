function S = loadSession(configRoot, dataRoot, sessionID)
%LOADSESSION Load metadata and scan locations for one imaging session.
%
% S = loadSession(configRoot, dataRoot, sessionID)
%
% Inputs:
%   configRoot  Directory containing sessions.txt and sessions/
%   dataRoot    Root directory containing the actual imaging data
%   sessionID   Session identifier, e.g.
%               'sub00004-umich-uhp-20250717-1'
%
% Example:
%   configRoot = '/path/to/Functional/data-config';
%   dataRoot   = '/mnt/storage/HarmonizedMRI/fMRI';
%
%   S = loadSession(configRoot, dataRoot, ...
%       'sub00004-umich-uhp-20250717-1');

sessionsFile = fullfile(configRoot, 'sessions.txt');

if ~isfile(sessionsFile)
    error('Sessions file not found: %s', sessionsFile);
end

% Read session-level metadata.
T = readtable(sessionsFile, ...
    'FileType', 'text', ...
    'Delimiter', {' ', '\t'}, ...
    'MultipleDelimsAsOne', true, ...
    'TextType', 'string');

% Construct session IDs.
ids = T.subject + "-" + T.site + "-" + T.scanner + "-" + ...
    string(T.date) + "-" + string(T.session);

idx = find(ids == string(sessionID));

if isempty(idx)
    error('Session "%s" not found in %s.', sessionID, sessionsFile);
elseif numel(idx) > 1
    error('Session "%s" occurs more than once in %s.', ...
        sessionID, sessionsFile);
end

% Session metadata.
S.id      = char(ids(idx));
S.subject = char(T.subject(idx));
S.site    = char(T.site(idx));
S.scanner = char(T.scanner(idx));
S.date    = char(string(T.date(idx)));
S.session = char(string(T.session(idx)));
S.vendor  = char(T.vendor(idx));

S.kspace_delay = T.kspace_delay(idx);

% Resolve readout trajectory file relative to configRoot.
S.readout_trajectory_file = fullfile( ...
    configRoot, char(T.readout_trajectory_file(idx)));

% Directory containing session configuration files.
S.configdir = fullfile(configRoot, 'sessions', S.id);

if ~isfolder(S.configdir)
    error('Session configuration directory not found: %s', S.configdir);
end

% Load Pulseq scans, if present.
filename = fullfile(S.configdir, 'pulseq', 'scans.txt');

if isfile(filename)
    S.scans.pulseq = readScans( ...
        filename, dataRoot, S.id, S.vendor);
end

% Load product scans, if present.
filename = fullfile(S.configdir, 'product', 'scans.txt');

if isfile(filename)
    S.scans.product = readScans( ...
        filename, dataRoot, S.id, S.vendor);
end

