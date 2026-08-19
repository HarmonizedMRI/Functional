function S = loadSession(sessionID, sessionsFile)
%LOADSESSION Load metadata and scan locations for one imaging session.
%
% S = loadSession(sessionID)
% S = loadSession(sessionID, sessionsFile)
%
% Example:
%   S = loadSession('sub00004-umich-uhp-20250717-1');

if nargin < 2
    sessionsFile = 'sessions.txt';
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
    error('Session "%s" occurs more than once in %s.', sessionID, sessionsFile);
end

% Session metadata.
S.id = char(ids(idx));
S.subject = char(T.subject(idx));
S.site = char(T.site(idx));
S.scanner = char(T.scanner(idx));
S.date = char(string(T.date(idx)));
S.session = char(string(T.session(idx)));
S.vendor = char(T.vendor(idx));

S.kspace_delay = T.kspace_delay(idx);
S.readout_trajectory_file = char(T.readout_trajectory_file(idx));

% Directory containing sessions.txt.
reconDir = fileparts(which(sessionsFile));
if isempty(reconDir)
    reconDir = pwd;
end

S.dir = fullfile(reconDir, 'sessions', S.id);

% Load Pulseq scans.
fn = fullfile(S.dir, 'pulseq', 'scans.txt');
if isfile(fn)
    S.scans.pulseq = readScans(fn, S.vendor);
end

% Load product scans, if present.
fn = fullfile(S.dir, 'product', 'scans.txt');
if isfile(fn)
    S.scans.product = readScans(fn, S.vendor);
end

