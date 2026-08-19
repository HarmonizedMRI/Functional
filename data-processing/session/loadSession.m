function S = loadSession(dataRoot, sessionID)
%LOADSESSION Load metadata and scan locations for one imaging session.
%
% S = loadSession(dataRoot, sessionID)
%
% Inputs:
%   dataRoot   Directory containing sessions.txt and sessions/
%   sessionID  Session identifier, e.g.
%              'sub00004-umich-uhp-20250717-1'
%
% Example:
%   S = loadSession('/path/to/data', ...
%       'sub00004-umich-uhp-20250717-1');

sessionsFile = fullfile(dataRoot, 'sessions.txt');

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

% Resolve readout trajectory file relative to dataRoot.
S.readout_trajectory_file = fullfile( ...
    dataRoot, char(T.readout_trajectory_file(idx)));

% Session directory.
S.dir = fullfile(dataRoot, 'sessions', S.id);

if ~isfolder(S.dir)
    error('Session directory not found: %s', S.dir);
end

% Load Pulseq scans, if present.
filename = fullfile(S.dir, 'pulseq', 'scans.txt');

if isfile(filename)
    S.scans.pulseq = readScans(filename, S.vendor);
end

% Load product scans, if present.
filename = fullfile(S.dir, 'product', 'scans.txt');

if isfile(filename)
    S.scans.product = readScans(filename, S.vendor);
end

